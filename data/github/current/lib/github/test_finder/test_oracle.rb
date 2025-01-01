# typed: true
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"
require "open3"

require "github/test_finder/test_oracle/covmap_array"
require_relative "../../../script/dx/telemetry/datadog"

module GitHub
  module TestFinder
    class TestOracle

      ALLOWED_PATHS = %w{ app lib packages test config }
      EXCLUDED_PATHS = %w{
        vendor
        test/test_helpers
        test/test_helper.rb
        test/minitest_helper.rb
      }

      DB_SCHEMA = <<~SQL
        CREATE TABLE IF NOT EXISTS files(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file TEXT UNIQUE
            );
        CREATE TABLE IF NOT EXISTS impact(
          src INTEGER,
          target INTEGER,
          UNIQUE(src, target),
          FOREIGN KEY(src) REFERENCES files(id),
          FOREIGN KEY(target) REFERENCES files(id)
          );
        CREATE TABLE IF NOT EXISTS params(
          id integer primary key autoincrement,
          root varchar UNIQUE NOT NULL
          );
        CREATE TABLE IF NOT EXISTS allowlist(
          id integer primary key autoincrement,
          root_id integer NOT NULL,
          path varchar,
          FOREIGN KEY(root_id) REFERENCES params(id)
          );
        CREATE TABLE IF NOT EXISTS excludelist(
          id integer primary key autoincrement,
          root_id integer NOT NULL,
          path varchar,
          FOREIGN KEY(root_id) REFERENCES params(id)
          );
        CREATE UNIQUE INDEX IF NOT EXISTS files_idx ON files(file);
        CREATE UNIQUE INDEX IF NOT EXISTS impact_idx ON impact(src, target);
        CREATE INDEX IF NOT EXISTS impact_src_idx ON impact(src);
        CREATE UNIQUE INDEX IF NOT EXISTS allowlist_idx ON allowlist (root_id, path);
        CREATE UNIQUE INDEX IF NOT EXISTS excludelist_idx ON excludelist (root_id, path);
      SQL

      IMPACT_INSERT_STATEMENT = <<~SQL
        INSERT OR IGNORE INTO impact(src, target)
          SELECT SOURCE.id, TARGET.id
          FROM files AS SOURCE
          JOIN files AS TARGET
          WHERE SOURCE.file=?
          AND TARGET.file=?
      SQL

      QUERY_FORMAT = <<~SQL
        SELECT DISTINCT file
        FROM files
        WHERE id IN
          (SELECT target
          FROM files
          JOIN impact
          WHERE impact.src = files.id AND files.file IN (%s))
      SQL

      QUERY_IMPACT_FORMAT = <<~SQL
        SELECT f.file, count(src)
        FROM impact
        JOIN files f ON id=src
        WHERE f.file IN (%s)
        GROUP BY src
        ORDER BY count(src) DESC
      SQL

      sig do params(
          db_path: String,
          root: T.any(String, Pathname),
          allowlist: T::Array[T.any(String, Pathname)],
          excludelist: T::Array[T.any(String, Pathname)],
        ).void
      end
      def initialize(db_path = "/tmp/test_oracle_covmap.db", root = "/", allowlist = ALLOWED_PATHS, excludelist = EXCLUDED_PATHS)
        @root             = T.let(full_path(root), Pathname)
        @allowed_paths    = T.let(allowlist.map   { |x| full_path(x) }, T::Array[Pathname])
        @excluded_paths   = T.let(excludelist.map { |x| full_path(x) }, T::Array[Pathname])
        @covmap           = CovmapArray.new
        @db_path          = db_path
        @sharded_dbs_path = Rails::root.join("tmp", "test-oracle").to_s
        setup_db
      end

      sig { params(path: T.any(String, Pathname), targets: T.any(String, Pathname)).returns(TestOracle) }
      def append(path, *targets)
        relative = relative_path(Pathname(path))

        unless (child_of?(@root, relative) &&
            allowed_paths.any? { |dir| child_of?(Pathname(dir), relative) } &&
            excluded_paths.none? { |dir| child_of?(Pathname(dir), relative) }
          )
          TestOracle.log "Skipping #{relative} because it didn't pass root/allowlist/excludelist check."
          return self
        end

        relative_targets = targets.reduce([]) do |acc, target|
          base_target = Pathname(target)
          full_target = Pathname(full_path(base_target))
          relative_target = Pathname(relative_path(base_target))

          if (child_of?(@root, full_target) &&
            allowed_paths.any? { |dir| child_of?(dir, relative_target) } &&
            excluded_paths.none? { |dir| child_of?(dir, relative_target) }
          )
            acc + [relative_target]
          else
            acc
          end
        end
        covmap << [relative.to_s, relative_targets[0].to_s]
        self
      end

      # Determine which files are impacted by modifications to the specified paths.
      sig { params(paths: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def query(paths)
        placeholders = (["?"] * paths.length).join(",") # create as many placeholders as paths
        query = QUERY_FORMAT % placeholders
        results = T.let([], T::Array[T.untyped])
        open_sharded_dbs do |db|
          results += db.execute(query, paths).flatten
        end
        results.uniq
      end

      sig { params(paths: T::Array[String]).returns(T::Hash[String, Integer]) }
      def query_impact(paths)
        placeholders = (["?"] * paths.length).join(",") # create as many placeholders as paths
        query = QUERY_IMPACT_FORMAT % placeholders
        results = {}
        open_sharded_dbs do |db|
          results.deep_merge!(db.execute(query, paths).to_h) { |_, a, b| a + b }
        end
        results
      end

      sig { returns(Integer) }
      def record_count
        results = 0
        open_sharded_dbs do |db|
          results += db.execute("SELECT COUNT(*) FROM impact").first.first.to_i
        end

        results
      end

      sig { returns(T::Array[Pathname]) }
      attr_reader :allowed_paths

      sig { returns(T::Array[Pathname]) }
      attr_reader :excluded_paths

      sig { returns(T.any(String, Pathname)) }
      attr_reader :db_path

      sig { returns(T.any(String, Pathname)) }
      attr_accessor :sharded_dbs_path

      sig { returns(CovmapArray) }
      attr_reader :covmap

      # write covmap to db and clear covmap
      sig { returns(Integer) }
      def flush!
        flushed_count = 0

        open_db do |db|
          files_statement = db.prepare("INSERT OR IGNORE INTO files(file) VALUES (?), (?)")
          impact_statement = db.prepare(IMPACT_INSERT_STATEMENT)

          begin
            covmap.covmap.each do |h|
              TestOracle.log "writing #{h}"
              src = h.keys.first
              target = h.values.first
              files_statement.execute(src, target)
              impact_statement.execute(src, target)
              flushed_count += 1
            end
          ensure
            files_statement.close
            impact_statement.close
          end
        end
        @covmap = CovmapArray.new
        flushed_count
      end

      sig { returns(Integer) }
      def count
        open_db do |db|
          db.execute("SELECT COUNT(src) FROM impact").flatten.first
        end
      end

      sig { params(msg: String).void }
      def self.log(msg)
        return unless ENV["DEBUG"]
        STDERR.puts "[Test Oracle] #{msg}"
      end

      sig { params(metric_name: String, value: Integer, tags: T::Array[String]).void }
      def self.metrics_count(metric_name, value, tags)
        metric_name = "test_oracle.#{metric_name}"
        return dogstats.count(metric_name, value, tags: tags) if ENV["GITHUB_CI"] == "1"

        # on Codespaces
        @metrics ||= DX::Datadog::MetricsBackend.new
        @metrics.submit_count(metric_name, Time.now.to_i, value, tags)
      end

      sig { params(metric_name: String, since: Time, tags: T::Array[String]).void }
      def self.duration_since(metric_name, since, tags)
        metric_name = "test_oracle.#{metric_name}"
        return dogstats.timing_since(metric_name, since, tags: tags) if ENV["GITHUB_CI"] == "1"

        # on Codespaces
        @metrics ||= DX::Datadog::MetricsBackend.new
        @metrics.submit_guage(metric_name, Time.now.to_i, ((Time.now - since) * 1000).to_i, tags)
      end

      def self.dogstats
        # We don't want to require test files in production
        require_relative "../../../test/test_helpers/github_test/stats"

        GitHubTest.dogstats
      end

      private

      sig { params(path: T.any(Pathname, String)).returns(Pathname) }
      def full_path(path)
        Pathname(path).expand_path
      end

      sig { params(path: Pathname).returns(Pathname) }
      def relative_path(path)
        if path.relative?
          path
        else
          unless child_of?(@root, Pathname(path))
            raise ArgumentError, "#{path} is not a child of #{@root}"
          end
          path.relative_path_from(@root)
        end
      end

      sig { params(parent: Pathname, child: Pathname).returns(T::Boolean) }
      def child_of?(parent, child)
        if child.relative? && parent.absolute?
          child.expand_path.ascend.include?(parent)
        else
          child.ascend.include?(parent)
        end
      end

      sig { params(db: SQLite3::Database).void }
      def save_params(db)
        db.execute "INSERT OR IGNORE INTO params(root) VALUES(?)", @root.to_s
        root_id = db.last_insert_row_id
        if root_id
          allowed_paths.each do |allow_path|
            db.execute "INSERT OR IGNORE INTO allowlist(root_id, path) VALUES(?, ?)", [root_id, allow_path.to_s]
          end
          excluded_paths.each do |exclude_path|
            db.execute "INSERT OR IGNORE INTO excludelist(root_id, path) VALUES(?, ?)", [root_id, exclude_path.to_s]
          end
        end
      end

      sig { void }
      def load_params
        open_db do |db|
          res = db.execute("SELECT id, root FROM params").first
          if res.nil? || res.empty?
            return
          end
          id = res[0].to_i
          @root = Pathname(res[1])
          al = db.execute("SELECT path FROM allowlist WHERE root_id = ?", id).flatten
          el = db.execute("SELECT path FROM excludelist WHERE root_id = ?", id).flatten
          @allowed_paths = al.map { |x| Pathname(x) }
          @excluded_paths = el.map { |x| Pathname(x) }
        end
      end

      def open_db(db_path = @db_path, &block)
        SQLite3::Database.new(db_path) do |db|
          db.busy_timeout = 30000
          block.call(db)
        end
      end

      def open_sharded_dbs(&block)
        open_db(&block)
        dbs_list.each do |db_path|
          open_db(db_path, &block)
        end
      end

      def dbs_list
        Dir.glob "#{@sharded_dbs_path}/**/test-oracle-covmap.db"
      end

      sig { returns(T::Boolean) }
      def is_db_valid?
        result = T.let(true, T::Boolean) # All OK unless proven otherwise
        open_sharded_dbs do |db|
          tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
          result &&= tables.include?("params")
          result &&= tables.include?("files")
          result &&= tables.include?("impact")
          result &&= tables.include?("allowlist")
          result &&= tables.include?("excludelist")
        end
        result
      end

      sig { void }
      def setup_db
        # Require sqlite here instead of in the outer scope, as we don't want to require sqlite in production
        require "sqlite3"

        if File.exist?(db_path) && is_db_valid?
          load_params
          return
        end
        open_db do |db|
          db.execute_batch(DB_SCHEMA)
          save_params(db)
        end
      end # setup_db
    end # TestOracle
  end # TestFinder
end # GitHub
