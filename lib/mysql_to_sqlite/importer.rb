module MysqlToSqlite
  class Importer
    class SourceRecord < ActiveRecord::Base
      self.abstract_class = true
    end

    class TargetRecord < ActiveRecord::Base
      self.abstract_class = true
    end

    INTERNAL_TABLES = %w[ar_internal_metadata schema_migrations].freeze

    def initialize(source_url:, destination:, batch_size: 1_000, replace: false,
      ignore_source_only: false, output: $stdout)
      @source_url = source_url
      @destination = destination
      @batch_size = Integer(batch_size)
      raise ArgumentError, "batch size must be positive" unless @batch_size.positive?

      @replace = replace
      @ignore_source_only = ignore_source_only
      @output = output
    end

    def run!
      connect!
      verify_databases!
      discover_tables!
      verify_migration_versions!
      verify_table_sets!
      verify_table_schemas!
      report_plan

      without_target_foreign_keys do
        TargetRecord.transaction do
          clear_target! if @replace
          verify_target_is_empty!
          reset_target_sequences!
          tables.each { |table| copy_table(table) }
          validate!
        end
      end

      output.puts "Import completed successfully."
    ensure
      SourceRecord.connection_pool.disconnect! if SourceRecord.connected?
      TargetRecord.connection_pool.disconnect! if TargetRecord.connected?
    end

    private

    attr_reader :batch_size, :output, :source, :tables, :target

    def connect!
      require "mysql2"
      require "sqlite3"

      SourceRecord.establish_connection(@source_url)
      TargetRecord.establish_connection(adapter: "sqlite3", database: @destination)
      @source = SourceRecord.connection
      @target = TargetRecord.connection
    end

    def verify_databases!
      raise ArgumentError, "source URL must use the mysql2 adapter" unless source.adapter_name == "Mysql2"
      raise "The destination database must use SQLite" unless target.adapter_name == "SQLite"
    end

    def discover_tables!
      @source_tables = source.data_sources - INTERNAL_TABLES
      @target_tables = target.data_sources - INTERNAL_TABLES
      @tables = (@source_tables & @target_tables).sort
    end

    def verify_table_sets!
      source_only = @source_tables - @target_tables
      target_only = @target_tables - @source_tables

      if source_only.any? && !@ignore_source_only
        raise compact(<<~MESSAGE)
          Source-only tables found: #{source_only.join(", ")}.
          Prepare the destination at the source migration version, or pass
          --ignore-source-only after verifying these tables can be skipped.
        MESSAGE
      end

      if target_only.any?
        raise compact(<<~MESSAGE)
          Destination-only tables found: #{target_only.join(", ")}.
          Prepare the destination at the same migration version as the source.
        MESSAGE
      end

      raise "No application tables were found to import" if tables.empty?
      output.puts "Skipping source-only tables: #{source_only.join(", ")}" if source_only.any?
    end

    def verify_table_schemas!
      mismatches = tables.filter_map do |table|
        source_columns = source.columns(table).map(&:name)
        target_columns = target.columns(table).map(&:name)
        next if source_columns.sort == target_columns.sort

        missing = target_columns - source_columns
        extra = source_columns - target_columns
        "#{table} (missing: #{missing.inspect}, extra: #{extra.inspect})"
      end
      raise "Schema mismatch: #{mismatches.join("; ")}" if mismatches.any?
    end

    def verify_migration_versions!
      source_version = migration_version(source)
      target_version = migration_version(target)
      return if source_version == target_version

      raise compact(<<~MESSAGE)
        Migration versions differ (source: #{source_version || "unknown"},
        destination: #{target_version || "unknown"}). Prepare the destination at the
        source version before importing.
      MESSAGE
    end

    def report_plan
      output.puts "Source migration version: #{migration_version(source) || "unknown"}"
      output.puts "Destination migration version: #{migration_version(target) || "unknown"}"
      output.puts "Tables to copy: #{tables.join(", ")}"
    end

    def migration_version(connection)
      return unless connection.data_source_exists?("schema_migrations")

      connection.select_value("SELECT MAX(version) FROM schema_migrations")
    end

    def without_target_foreign_keys
      target.execute("PRAGMA foreign_keys = OFF")
      yield
    ensure
      target.execute("PRAGMA foreign_keys = ON") if target
    end

    def verify_target_is_empty!
      populated = tables.filter_map do |table|
        count = target_count(table)
        "#{table}=#{count}" if count.positive?
      end
      raise "Destination must be empty before import (#{populated.join(", ")})" if populated.any?
    end

    def clear_target!
      tables.reverse_each do |table|
        target.execute("DELETE FROM #{target.quote_table_name(table)}")
      end
    end

    def reset_target_sequences!
      return unless sqlite_sequence_table?

      names = tables.map { |table| target.quote(table) }.join(", ")
      target.execute("DELETE FROM sqlite_sequence WHERE name IN (#{names})")
    end

    def copy_table(table)
      columns = source.columns(table).map(&:name)
      record_class = Class.new(TargetRecord) do
        self.table_name = table
        self.inheritance_column = :_type_disabled
      end
      copied = 0
      order = source.primary_key(table) || columns.first

      loop do
        rows = source.select_all(compact(<<~SQL)).to_a
          SELECT #{columns.map { |column| source.quote_column_name(column) }.join(", ")}
          FROM #{source.quote_table_name(table)}
          ORDER BY #{source.quote_column_name(order)}
          LIMIT #{batch_size} OFFSET #{copied}
        SQL
        break if rows.empty?

        record_class.insert_all!(rows, record_timestamps: false)
        copied += rows.length
        output.puts "#{table}: copied #{copied}" if rows.length == batch_size
      end
      output.puts "#{table}: #{copied} row(s)"
    end

    def validate!
      failures = tables.filter_map do |table|
        source_count = source.select_value(
          "SELECT COUNT(*) FROM #{source.quote_table_name(table)}"
        ).to_i
        destination_count = target_count(table)
        "#{table}: source=#{source_count}, destination=#{destination_count}" unless source_count == destination_count
      end
      raise "Row-count validation failed (#{failures.join("; ")})" if failures.any?

      violations = target.select_all("PRAGMA foreign_key_check")
      raise "Foreign-key validation failed: #{violations.to_a.inspect}" if violations.any?

      validate_sequences!
    end

    def validate_sequences!
      return unless sqlite_sequence_table?

      tables.each do |table|
        primary_key = target.primary_key(table)
        column = target.columns(table).find { |candidate| candidate.name == primary_key }
        next unless column&.type == :integer

        max_id = target.select_value(
          "SELECT MAX(#{target.quote_column_name(primary_key)}) FROM #{target.quote_table_name(table)}"
        ).to_i
        sequence = target.select_value(
          "SELECT seq FROM sqlite_sequence WHERE name = #{target.quote(table)}"
        ).to_i
        raise "Sequence validation failed for #{table}" unless max_id == sequence
      end
    end

    def target_count(table)
      target.select_value("SELECT COUNT(*) FROM #{target.quote_table_name(table)}").to_i
    end

    def sqlite_sequence_table?
      target.select_value(<<~SQL)&.to_s&.length&.positive?
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'sqlite_sequence'
      SQL
    end

    def compact(string)
      string.lines.map(&:strip).join(" ")
    end
  end
end
