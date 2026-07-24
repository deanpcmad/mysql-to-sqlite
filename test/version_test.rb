require "minitest/autorun"
require "mysql_to_sqlite"

class VersionTest < Minitest::Test
  def test_has_a_version
    refute_empty MysqlToSqlite::VERSION
  end
end
