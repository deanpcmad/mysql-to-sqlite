Gem::Specification.new do |spec|
  spec.name = "mysql-to-sqlite"
  spec.version = "0.1.0"
  spec.summary = "Copy a version-matched MySQL database into SQLite"
  spec.description = "A schema-aware MySQL-to-SQLite data importer built on Active Record."
  spec.authors = ["Dean"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["bin/*", "lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.bindir = "bin"
  spec.executables = ["mysql-to-sqlite"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 9"
  spec.add_dependency "mysql2", "~> 0.5"
  spec.add_dependency "sqlite3", ">= 2.1"
end
