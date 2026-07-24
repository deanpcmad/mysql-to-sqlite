require "minitest/autorun"
require "stringio"
require "mysql_to_sqlite"

# Exercises Importer's private logic against two real in-memory SQLite
# databases (standing in for the MySQL source and SQLite target), since
# connect!/verify_databases! otherwise require a live MySQL connection.
class ImporterIntegrationTest < Minitest::Test
  Source = MysqlToSqlite::Importer::SourceRecord
  Target = MysqlToSqlite::Importer::TargetRecord

  FakeConnection = Struct.new(:adapter_name)

  def setup
    Source.establish_connection(adapter: "sqlite3", database: ":memory:")
    Target.establish_connection(adapter: "sqlite3", database: ":memory:")
  end

  def teardown
    Source.connection_pool.disconnect!
    Target.connection_pool.disconnect!
  end

  def test_verify_databases_raises_when_source_is_not_mysql
    importer = build_importer

    error = assert_raises(ArgumentError) { importer.send(:verify_databases!) }
    assert_equal "source URL must use the mysql2 adapter", error.message
  end

  def test_verify_databases_raises_when_target_is_not_sqlite
    importer = build_importer
    importer.instance_variable_set(:@source, FakeConnection.new("Mysql2"))
    importer.instance_variable_set(:@target, FakeConnection.new("PostgreSQL"))

    error = assert_raises(RuntimeError) { importer.send(:verify_databases!) }
    assert_equal "The destination database must use SQLite", error.message
  end

  def test_discover_tables_intersects_and_sorts_source_and_target_tables
    Source.connection.create_table(:posts) { |t| t.string :title }
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:comments) { |t| t.string :body }

    importer = build_importer
    importer.send(:discover_tables!)

    assert_equal ["users"], importer.send(:tables)
  end

  def test_verify_table_sets_raises_for_source_only_tables_by_default
    Source.connection.create_table(:users) { |t| t.string :name }
    Source.connection.create_table(:posts) { |t| t.string :title }
    Target.connection.create_table(:users) { |t| t.string :name }

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:verify_table_sets!) }
    assert_match(/Source-only tables found: posts/, error.message)
  end

  def test_verify_table_sets_allows_source_only_tables_when_ignored
    Source.connection.create_table(:users) { |t| t.string :name }
    Source.connection.create_table(:posts) { |t| t.string :title }
    Target.connection.create_table(:users) { |t| t.string :name }

    output = StringIO.new
    importer = build_importer(ignore_source_only: true, output: output)
    importer.send(:discover_tables!)
    importer.send(:verify_table_sets!)

    assert_match(/Skipping source-only tables: posts/, output.string)
  end

  def test_verify_table_sets_raises_for_target_only_tables_even_when_ignoring_source_only
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:comments) { |t| t.string :body }

    importer = build_importer(ignore_source_only: true)
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:verify_table_sets!) }
    assert_match(/Destination-only tables found: comments/, error.message)
  end

  def test_verify_table_sets_raises_when_no_tables_exist
    importer = build_importer(ignore_source_only: true)
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:verify_table_sets!) }
    assert_match(/No application tables were found to import/, error.message)
  end

  def test_verify_table_schemas_raises_on_column_mismatch
    Source.connection.create_table(:users) do |t|
      t.string :name
      t.string :email
    end
    Target.connection.create_table(:users) do |t|
      t.string :name
      t.string :phone
    end

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:verify_table_schemas!) }
    assert_match(/users \(missing: \["phone"\], extra: \["email"\]\)/, error.message)
  end

  def test_migration_version_is_nil_without_schema_migrations_table
    Source.connection.create_table(:users) { |t| t.string :name }

    importer = build_importer
    assert_nil importer.send(:migration_version, Source.connection)
  end

  def test_migration_version_returns_max_version
    Source.connection.create_table(:schema_migrations, id: false) { |t| t.string :version }
    Source.connection.execute("INSERT INTO schema_migrations (version) VALUES ('20240101000000')")
    Source.connection.execute("INSERT INTO schema_migrations (version) VALUES ('20240202000000')")

    importer = build_importer
    assert_equal "20240202000000", importer.send(:migration_version, Source.connection)
  end

  def test_copy_table_batches_and_copies_all_rows
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    5.times { |i| Source.connection.execute("INSERT INTO users (name) VALUES ('user#{i}')") }

    output = StringIO.new
    importer = build_importer(batch_size: 2, output: output)
    importer.send(:discover_tables!)
    importer.send(:copy_table, "users")

    assert_equal 5, Target.connection.select_value("SELECT COUNT(*) FROM users").to_i
    assert_equal ["user0", "user1", "user2", "user3", "user4"],
      Target.connection.select_all("SELECT name FROM users ORDER BY id").to_a.map { |row| row["name"] }
    assert_match(/users: copied 2/, output.string)
    assert_match(/users: copied 4/, output.string)
    assert_match(/users: 5 row\(s\)/, output.string)
  end

  def test_validate_passes_after_full_copy_and_checks_sequences
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    3.times { |i| Source.connection.execute("INSERT INTO users (name) VALUES ('user#{i}')") }

    importer = build_importer(output: StringIO.new)
    importer.send(:discover_tables!)
    importer.send(:copy_table, "users")

    importer.send(:validate!)
  end

  def test_validate_raises_on_foreign_key_violations
    Source.connection.create_table(:authors) { |t| t.string :name }
    Source.connection.create_table(:posts) { |t| t.integer :author_id }
    Source.connection.execute("INSERT INTO authors (name) VALUES ('Ada')")
    Source.connection.execute("INSERT INTO posts (author_id) VALUES (1)")

    Target.connection.create_table(:authors) { |t| t.string :name }
    Target.connection.create_table(:posts) { |t| t.integer :author_id }
    Target.connection.add_foreign_key(:posts, :authors)
    Target.connection.execute("PRAGMA foreign_keys = OFF")
    Target.connection.execute("INSERT INTO authors (name) VALUES ('Ada')")
    Target.connection.execute("INSERT INTO posts (author_id) VALUES (999)")

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:validate!) }
    assert_match(/Foreign-key validation failed/, error.message)
  end

  def test_validate_sequences_raises_on_mismatch
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Source.connection.execute("INSERT INTO users (name) VALUES ('a')")
    Target.connection.execute("INSERT INTO users (name) VALUES ('a')")
    Target.connection.execute("INSERT INTO users (name) VALUES ('b')")
    Target.connection.execute("DELETE FROM users WHERE name = 'b'")

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:validate_sequences!) }
    assert_match(/Sequence validation failed for users/, error.message)
  end

  def test_without_target_foreign_keys_restores_pragma_after_error
    importer = build_importer

    assert_raises(RuntimeError) do
      importer.send(:without_target_foreign_keys) { raise "boom" }
    end

    assert_equal 1, Target.connection.select_value("PRAGMA foreign_keys")
  end

  def test_validate_raises_on_row_count_mismatch
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Source.connection.execute("INSERT INTO users (name) VALUES ('user0')")
    Source.connection.execute("INSERT INTO users (name) VALUES ('user1')")
    Target.connection.execute("INSERT INTO users (name) VALUES ('user0')")

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:validate!) }
    assert_match(/Row-count validation failed \(users: source=2, destination=1\)/, error.message)
  end

  def test_verify_target_is_empty_raises_when_destination_has_rows
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Target.connection.execute("INSERT INTO users (name) VALUES ('leftover')")

    importer = build_importer
    importer.send(:discover_tables!)

    error = assert_raises(RuntimeError) { importer.send(:verify_target_is_empty!) }
    assert_match(/Destination must be empty before import \(users=1\)/, error.message)
  end

  def test_clear_target_removes_existing_rows
    Source.connection.create_table(:users) { |t| t.string :name }
    Target.connection.create_table(:users) { |t| t.string :name }
    Target.connection.execute("INSERT INTO users (name) VALUES ('leftover')")

    importer = build_importer
    importer.send(:discover_tables!)
    importer.send(:clear_target!)

    assert_equal 0, Target.connection.select_value("SELECT COUNT(*) FROM users").to_i
  end

  def test_reset_target_sequences_clears_sqlite_sequence_entries
    Target.connection.create_table(:users) { |t| t.string :name }
    Target.connection.execute("INSERT INTO users (name) VALUES ('a')")
    Target.connection.execute("DELETE FROM users")
    assert_equal 1, Target.connection.select_value("SELECT seq FROM sqlite_sequence WHERE name = 'users'").to_i

    importer = build_importer
    importer.instance_variable_set(:@tables, ["users"])
    importer.send(:reset_target_sequences!)

    assert_nil Target.connection.select_value("SELECT seq FROM sqlite_sequence WHERE name = 'users'")
  end

  private

  def build_importer(**overrides)
    importer = MysqlToSqlite::Importer.new(
      source_url: "mysql2://localhost/source",
      destination: "target.sqlite3",
      output: StringIO.new,
      **overrides
    )
    importer.instance_variable_set(:@source, Source.connection)
    importer.instance_variable_set(:@target, Target.connection)
    importer
  end
end
