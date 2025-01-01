require "dependency_graph/structure_cleaner"

class DgDatabaseTasks
  def self.get_mysql_major_version
    ActiveRecord::Base.connection.execute("SELECT VERSION()").first.first.split(".").first.to_i
  end

  def self.clean_structure(structure_file, filter_tables: nil)
    # Cleanup .sql files to make them more compact, easier to diff, and
    # machine-independent
    structure_path = File.join(Rails.root, "db", structure_file)
    contents = File.read(structure_path)

    contents = DependencyGraph::StructureCleaner.clean_auto_increment(contents)
    contents = DependencyGraph::StructureCleaner.clean_conditional_statements(contents)
    contents = DependencyGraph::StructureCleaner.clean_blank_lines(contents)
    contents = DependencyGraph::StructureCleaner.remove_unnecessary_column_character_set(contents)

    if filter_tables
      contents = DependencyGraph::StructureCleaner.extract_table_definitions(contents, filter_tables)
    end

    File.write(structure_path, contents)
  end
end

namespace :db do
  namespace :github do
    task create: :environment do
      create_db Rails.configuration.database_configuration.fetch("github")
      create_db Rails.configuration.database_configuration.fetch("github_notify")

      # Emulate schema of VVR here. We were previously doing this in tests, but
      # it proved to have race conditions. Using things that generate MySQL DDL statements
      # will generate implicit commits, which will remove all active savepoints, leading to
      # occasional (and sometimes frequent) "SAVEPOINT active_record_1 does not exist" errors.
      # (https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html)
      unless vvr_connection.data_source_exists?(:vulnerable_version_ranges)
        vvr_connection.create_table(:vulnerable_version_ranges) do |t|
          t.integer :vulnerability_id
          t.string :affects
          t.string :ecosystem
          t.string :requirements
          t.string :fixed_in
          t.timestamp :created_at
          t.timestamp :updated_at
        end
      end

      unless vvr_connection.data_source_exists?(:vulnerabilities)
        vvr_connection.create_table(:vulnerabilities) do |t|
          t.string :description
          t.string :severity
          t.timestamp :created_at
          t.timestamp :updated_at
          t.string :status
        end
      end
    end
  end

  task check_mysql_version: :load_config do
    if DgDatabaseTasks.get_mysql_major_version < 8
      bold = "\033[1m"
      reset = "\033[0m"

      puts "🚨 #{bold}Refusing to dump schema for MySQL 5.7#{reset} 🚨"
      puts ""
      puts "The github/dependency-graph-api master branch is now configured to run MySQL 8.0,"
      puts "this means that schema dumps and migrations can no longer be run with MySQL 5.7."
      puts ""
      abort
      next
    end
  end
  Rake::Task["db:schema:dump"].enhance(["db:check_mysql_version"])

  namespace :schema do
    task :dump do
      DgDatabaseTasks.clean_structure("structure.sql")
    end
  end

  def vvr_connection
    VulnerableVersionRange::GitHubVulnerableVersionRange.connection
  end

  def create_db(configuration)
    include ActiveRecord::Tasks

    if Rails.env.development?
      environments = ["development", "test"]
    else
      environments = [Rails.env]
    end

    environments.each do |environment|
      DatabaseTasks.create configuration.fetch(environment)
    end
  end
end
