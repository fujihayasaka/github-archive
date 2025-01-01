# typed: true
# frozen_string_literal: true

module GitHub
  class Serviceowners
    class Tableowners
      TABLEOWNERS_YAML_PATH = Rails.root.join("db").join("tableowners.yaml").freeze
      OWNERSHIP_YAML_PATH   = Rails.root.join("ownership.yaml").freeze

      ModelInfo = Struct.new(:model, :path, :owner, keyword_init: true)

      TableInfo = Struct.new(:table, :db, :in_yaml?, :table_exists?,
                            :table_suggestions, :owner, :mismatch?,
                            :owner_exists?, :owner_suggestions, :owner_or_guess,
                            :model_infos, keyword_init: true)

      attr_reader :tableowners_yaml_path, :ownership_yaml_path

      def initialize(tableowners_yaml_path: TABLEOWNERS_YAML_PATH,
                    ownership_yaml_path: OWNERSHIP_YAML_PATH)
        @tableowners_yaml_path = Pathname.new(tableowners_yaml_path)
        @ownership_yaml_path = Pathname.new(ownership_yaml_path)
      end

      def results
        @results ||=
          begin
            all_tables = (valid_tables + tables_2_package_owners.keys + tableowners_yaml.keys).uniq.sort
            all_tables.to_h do |table|
              owner = tableowners_yaml[table]

              # model reflection information
              models = tables_2_models[table] || []
              model_infos = models.map do |model|
                path = model_2_path(model)
                ModelInfo.new(
                  model: model,
                  path: path,
                  owner: path_2_owner(path),
                ).freeze
              end.freeze

              models_owners = model_infos.map(&:owner).compact.uniq
              package_owner = tables_2_package_owners[table]

              mismatch =
                if models_owners.present?
                  !models_owners.include?(owner)
                elsif package_owner
                  package_owner != owner
                else
                  false
                end

              owner_exists = valid_owners.include?(owner)

              owner_suggestions =
                if mismatch
                  models_owners
                else
                  []
                end

              # For tables where we don't find a model, we suggest the package owner if there is one.
              owner_suggestions << package_owner if package_owner

              table_info = TableInfo.new(
                table: table,
                db: tables_2_dbs[table],
                in_yaml?: tableowners_yaml.keys.include?(table),
                table_exists?: valid_tables.include?(table),
                table_suggestions: table_didumean(table),
                owner: owner,
                owner_exists?: owner_exists,
                mismatch?: mismatch,
                owner_suggestions: owner_suggestions,
                owner_or_guess: owner || owner_suggestions.first,
                model_infos: model_infos,
              ).freeze

              [table, table_info.freeze]
            end.freeze
          end
      end

      def export_to_file(path: @tableowners_yaml_path)
        path = Pathname.new(path)
        puts "Writing data to #{path}"
        path.dirname.mkpath
        mappings = results.transform_values(&:owner_or_guess)
        path.write(mappings.deep_stringify_keys.to_yaml.gsub(/\s*$/, "") + "\n")
        puts "Tableowners file created in #{path}"
      end

      def table_to_owner(table)
        tableowners_yaml[table]
      end

      def table_names
        tableowners_yaml.keys
      end

      private

      def ownership_yaml
        @ownership_yaml ||= YAML.safe_load_file(@ownership_yaml_path).freeze
      end

      def tableowners_yaml
        @tableowners_yaml ||= YAML.safe_load_file(@tableowners_yaml_path).freeze
      end

      # Suggests the closest match on valid_tables
      def table_didumean(table)
        if table && !valid_tables.include?(table)
          @spell_checker_table ||=
            DidYouMean::SpellChecker.new(dictionary: valid_tables)
          @spell_checker_table.correct(table)
        else
          []
        end
      end

      # List of all services defined in ownership.yaml
      def valid_owners
        @valid_owners ||= ownership_yaml["ownership"]
          .filter_map { |item| item["name"] }
          .to_set
          .freeze
      end

      # Path of the sauce file where model is defined
      def model_2_path(model)
        path = Module.const_source_location(model.name)&.first
        if path
          Pathname.new(path).relative_path_from(Rails.root).to_s
        else
          nil
        end
      rescue NameError
        # There's no guarantee that the model has a name, that name isn't
        # redefined, or that its constant hasn't been removed.
        # This workaround is necessary largely because topmost_concrete_models
        # is based on unpredictable behaviour.
        nil
      end

      # Owner for given path
      def path_2_owner(path)
        GitHub.serviceowners.service_for_path(path, prefix: true)
      end

      def tables_2_package_owners
        @tables_2_package_owners ||= GitHub.packageowners.tables_to_owner
      end

      # Maps tables to the topmost models in the ancestry tree that are mapped to
      # them.
      def tables_2_models
        @tables_2_models ||= topmost_concrete_models.group_by(&:table_name)
      end

      # Tries hard to return all the topmost models in the class ancestry tree
      # that are concrete (mapped to a table).
      #
      # In other words: all models that don't share the same table_name with it's
      # superclass.
      def topmost_concrete_models
        @topmost_concrete_models ||=
          begin
            # This pattern relies on unpredictable behaviour in GC.
            # It's likely flaky and the wrong way to do this. Don't repeat it elsewhere.
            Zeitwerk::Loader.eager_load_all
            ActiveRecord::Base.descendants.select do |model|
              # NOTE: unfortunately we can't call ActiveRecord::Base.table_name,
              # so we have to deal with those pesky edge cases
              if model == ActiveRecord::Base
                false
              elsif model.table_name.blank?
                false
              elsif test_model?(model)
                false
              elsif model.superclass == ActiveRecord::Base
                true
              else
                model.table_name != model.superclass.table_name
              end
            end
          end
      end

      def test_model?(model)
        return false if model.nil?

        path = model_2_path(model)
        return false if path.nil?

        File.fnmatch("{,packages/*/}test/*", path, File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end

      # Query every database we know about and return the combined list of all
      # tables in them
      def valid_tables
        @valid_tables ||= dbs_2_tables.values.flatten.to_set
      end

      def tables_2_dbs
        @tables_2_dbs ||=
          begin
            tables_2_dbs = {}
            dbs_2_tables.each do |db, tables|
              tables.each do |table|
                tables_2_dbs[table] = db
              end
            end
            tables_2_dbs
          end
      end

      # Query every database we know about and return tables grouped by db
      #
      # We call Zeitwerk::Loader.eager_load_all so that the connection pool
      # list would have connections to databases for all AR models.
      def dbs_2_tables
        @dbs_2_tables ||=
          begin
            Zeitwerk::Loader.eager_load_all
            dbs_tables = ActiveRecord::Base.connection_handler.connection_pool_list(:all).to_h do |pool|
              [pool.db_config, pool.lease_connection.tables]
            end

            dbs_tables
          end.freeze
      end
    end
  end
end
