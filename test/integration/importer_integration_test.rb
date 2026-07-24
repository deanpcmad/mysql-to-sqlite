require "minitest/autorun"
require "mysql2"
require "sqlite3"
require "stringio"
require "tempfile"
require "uri"
require "mysql_to_sqlite"

class MysqlDumpIntegrationTest < Minitest::Test
  MATCHING_VERSION = "20260724000000"
  FIXTURES = File.expand_path("../fixtures/mysql", __dir__)

  def setup
    skip "set MYSQL_TEST_URL to run MySQL integration tests" unless ENV["MYSQL_TEST_URL"]

    @sqlite_file = Tempfile.new(["mysql-to-sqlite", ".sqlite3"])
    @sqlite_file.close
  end

  def teardown
    @sqlite_file&.unlink
  end

  def test_copies_relations_and_preserves_representative_values
    restore_mysql_dump("basic.sql")
    create_sqlite_database(full_schema)
    output = StringIO.new

    importer(batch_size: 1, output: output).run!

    database = SQLite3::Database.new(@sqlite_file.path)
    database.results_as_hash = true
    authors = database.execute("SELECT * FROM authors ORDER BY id")
    posts = database.execute("SELECT * FROM posts ORDER BY id")

    assert_equal [2, 7], authors.map { |row| row["id"] }
    assert_equal ["Ada Lovelace", "Renée O'Connor"], authors.map { |row| row["name"] }
    assert_equal [1, 0], authors.map { |row| row["active"] }
    assert_equal "\x00\xFF\x10".b, authors.first["token"]
    assert_nil authors.last["biography"]
    assert_equal [3, 9], posts.map { |row| row["id"] }
    assert_equal "Unicode: π and 🚀", posts.first["body"]
    assert_nil posts.last["published_at"]
    assert_equal 7, database.get_first_value("SELECT seq FROM sqlite_sequence WHERE name = 'authors'")
    assert_equal 9, database.get_first_value("SELECT seq FROM sqlite_sequence WHERE name = 'posts'")
    assert_includes output.string, "Import completed successfully."
  ensure
    database&.close
  end

  def test_refuses_a_populated_destination_without_replace
    restore_mysql_dump("basic.sql")
    create_sqlite_database(full_schema)
    database = SQLite3::Database.new(@sqlite_file.path)
    database.execute("INSERT INTO authors (name, active) VALUES ('Existing', 1)")
    database.close

    error = assert_raises(RuntimeError) { importer.run! }

    assert_includes error.message, "Destination must be empty"
  end

  def test_replace_clears_existing_records
    restore_mysql_dump("basic.sql")
    create_sqlite_database(full_schema)
    database = SQLite3::Database.new(@sqlite_file.path)
    database.execute("INSERT INTO authors (name, active) VALUES ('Existing', 1)")
    database.close

    importer(replace: true).run!

    database = SQLite3::Database.new(@sqlite_file.path)
    assert_equal 2, database.get_first_value("SELECT COUNT(*) FROM authors")
    refute database.get_first_value("SELECT 1 FROM authors WHERE name = 'Existing'")
  ensure
    database&.close
  end

  def test_source_only_tables_require_an_explicit_override
    restore_mysql_dump("source_only.sql")
    create_sqlite_database(simple_schema)

    error = assert_raises(RuntimeError) { importer.run! }
    assert_includes error.message, "Source-only tables found: legacy_events"

    importer(ignore_source_only: true).run!
    database = SQLite3::Database.new(@sqlite_file.path)
    assert_equal ["Grace Hopper"], database.execute("SELECT name FROM authors").flatten
  ensure
    database&.close
  end

  def test_refuses_different_migration_versions
    restore_mysql_dump("newer_version.sql")
    create_sqlite_database(simple_schema)

    error = assert_raises(RuntimeError) { importer.run! }

    assert_includes error.message, "Migration versions differ"
    assert_includes error.message, "20260725000000"
  end

  def test_copies_a_realistic_multi_table_invoicing_dataset
    restore_mysql_dump("invoicing.sql")
    create_sqlite_database(invoicing_schema)
    output = StringIO.new

    importer(output: output).run!

    database = SQLite3::Database.new(@sqlite_file.path)
    database.results_as_hash = true

    assert_equal 5, database.get_first_value("SELECT COUNT(*) FROM customers")
    assert_equal 8, database.get_first_value("SELECT COUNT(*) FROM invoices")
    assert_equal 15, database.get_first_value("SELECT COUNT(*) FROM invoice_line_items")
    assert_equal 4, database.get_first_value("SELECT COUNT(*) FROM quotes")
    assert_equal 6, database.get_first_value("SELECT COUNT(*) FROM emails")

    paid_invoice = database.execute("SELECT * FROM invoices WHERE invoice_number = 'INV-1005'").first
    assert_equal "paid", paid_invoice["status"]
    assert_in_delta 1249.98, paid_invoice["total"].to_f, 0.001

    draft_invoice = database.execute("SELECT * FROM invoices WHERE invoice_number = 'INV-1003'").first
    assert_nil draft_invoice["due_at"]
    assert_nil draft_invoice["notes"]

    customer = database.execute("SELECT * FROM customers WHERE email = 'renee@example.com'").first
    assert_equal "Renée Dubois", customer["name"]
    assert_nil database.execute("SELECT * FROM customers WHERE email = 'liang@example.com'").first["phone"]

    welcome_email = database.execute("SELECT * FROM emails WHERE subject = 'Welcome aboard'").first
    assert_nil welcome_email["invoice_id"]

    assert_includes output.string, "Import completed successfully."
  ensure
    database&.close
  end

  def test_refuses_column_mismatches
    restore_mysql_dump("source_only.sql")
    create_sqlite_database(simple_schema.sub("name TEXT NOT NULL", "display_name TEXT NOT NULL"))

    error = assert_raises(RuntimeError) do
      importer(ignore_source_only: true).run!
    end

    assert_includes error.message, "Schema mismatch"
    assert_includes error.message, 'missing: ["display_name"]'
    assert_includes error.message, 'extra: ["name"]'
  end

  private

  def importer(**options)
    MysqlToSqlite::Importer.new(
      source_url: ENV.fetch("MYSQL_TEST_URL"),
      destination: @sqlite_file.path,
      output: StringIO.new,
      **options
    )
  end

  def restore_mysql_dump(name)
    uri = URI.parse(ENV.fetch("MYSQL_TEST_URL"))
    client = Mysql2::Client.new(
      host: uri.host,
      port: uri.port,
      username: URI.decode_www_form_component(uri.user),
      password: uri.password && URI.decode_www_form_component(uri.password),
      database: uri.path.delete_prefix("/"),
      flags: Mysql2::Client::MULTI_STATEMENTS
    )
    client.query(File.read(File.join(FIXTURES, name)))
    client.abandon_results!
  ensure
    client&.close
  end

  def create_sqlite_database(schema)
    database = SQLite3::Database.new(@sqlite_file.path)
    database.execute_batch(schema)
  ensure
    database&.close
  end

  def schema_migrations
    <<~SQL
      CREATE TABLE schema_migrations (version TEXT NOT NULL PRIMARY KEY);
      INSERT INTO schema_migrations (version) VALUES ('#{MATCHING_VERSION}');
    SQL
  end

  def simple_schema
    schema_migrations + <<~SQL
      CREATE TABLE authors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      );
    SQL
  end

  def full_schema
    schema_migrations + <<~SQL
      PRAGMA foreign_keys = ON;
      CREATE TABLE authors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        biography TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        joined_on DATE,
        token BLOB
      );
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        author_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        body TEXT,
        published_at DATETIME,
        FOREIGN KEY (author_id) REFERENCES authors(id)
      );
    SQL
  end

  def invoicing_schema
    schema_migrations + <<~SQL
      PRAGMA foreign_keys = ON;
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT,
        created_at DATETIME NOT NULL
      );
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        invoice_number TEXT NOT NULL,
        status TEXT NOT NULL,
        subtotal DECIMAL NOT NULL,
        tax DECIMAL NOT NULL,
        total DECIMAL NOT NULL,
        issued_on DATE NOT NULL,
        due_at DATETIME,
        notes TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      );
      CREATE TABLE invoice_line_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        description TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price DECIMAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      );
      CREATE TABLE quotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        quote_number TEXT NOT NULL,
        status TEXT NOT NULL,
        total DECIMAL NOT NULL,
        expires_on DATE,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      );
      CREATE TABLE emails (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        subject TEXT NOT NULL,
        sent_at DATETIME NOT NULL,
        body TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      );
    SQL
  end
end
