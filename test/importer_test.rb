require "minitest/autorun"
require "stringio"
require "mysql_to_sqlite"

class ImporterTest < Minitest::Test
  def test_rejects_non_positive_batch_size
    error = assert_raises(ArgumentError) do
      MysqlToSqlite::Importer.new(
        source_url: "mysql2://localhost/source",
        destination: "target.sqlite3",
        batch_size: 0
      )
    end

    assert_equal "batch size must be positive", error.message
  end

  def test_rejects_non_numeric_batch_size
    assert_raises(ArgumentError) do
      MysqlToSqlite::Importer.new(
        source_url: "mysql2://localhost/source",
        destination: "target.sqlite3",
        batch_size: "not-a-number"
      )
    end
  end

  def test_accepts_numeric_batch_size
    importer = MysqlToSqlite::Importer.new(
      source_url: "mysql2://localhost/source",
      destination: "target.sqlite3",
      batch_size: "25",
      output: StringIO.new
    )

    assert_instance_of MysqlToSqlite::Importer, importer
  end
end
