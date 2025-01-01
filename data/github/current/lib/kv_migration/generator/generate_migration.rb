# typed: true
# frozen_string_literal: true

require "kv_migration/generator/utils"
require "kv_migration/generator/run_migration"

module KvMigration
  module Generator
    class GenerateMigration
      include KvMigration::Generator::Utils

      TEMPLATE = "lib/github/transitions/templates/kv/migration_template.rb.erb"

      def self.call(service, domain, cluster: nil, owner: nil, run: false, migration_file_path: nil, schema_domain_file_path: GitHub::SQLCheckers::SchemaDomain::PATH, migration_runner: KvMigration::Generator::RunMigration, database_structure_file_path: "lib/github/database_structure.rb", tableowners_file_path: GitHub::Serviceowners::Tableowners::TABLEOWNERS_YAML_PATH)
        new(
          service,
          domain,
          cluster:,
          owner:,
          run:,
          migration_file_path:,
          schema_domain_file_path:,
          migration_runner:,
          database_structure_file_path:,
          tableowners_file_path:).call
      end

      def initialize(service, domain, cluster: nil, owner: nil, run: false, migration_file_path: nil, schema_domain_file_path: GitHub::SQLCheckers::SchemaDomain::PATH, migration_runner: KvMigration::Generator::RunMigration, database_structure_file_path: "lib/github/database_structure.rb", tableowners_file_path: GitHub::Serviceowners::Tableowners::TABLEOWNERS_YAML_PATH)
        @service = service
        @domain = domain
        @cluster = cluster
        @owner = owner
        @run = run
        @migration_file_path = migration_file_path || default_migration_file_path
        @schema_domain_file_path = schema_domain_file_path
        @migration_runner = migration_runner
        @database_structure_file_path = database_structure_file_path
        @tableowners_file_path = tableowners_file_path
      end

      def call
        ensure_directory_exists(File.dirname(migration_file_path))
        update_schema_domains
        write_file(migration_file_path, render(TEMPLATE, binding))
        update_database_structure if cluster
        update_tableowners if owner
        migration_runner.call if run
      end

      def now = Time.now.utc.strftime "%Y%m%d%H%M%S"
      def migration_name = "#{now}_create_#{table_name.underscore}"
      def default_migration_file_path = "db/migrate/#{migration_name}.rb"

      def model_name = "#{service.underscore.camelize}KeyValues"
      def table_name = "#{service.underscore}_key_values"

      private

      attr_reader :service, :domain, :cluster, :owner, :run, :migration_file_path, :schema_domain_file_path, :migration_runner, :database_structure_file_path, :tableowners_file_path

      def update_schema_domains
        domain_key = domain.underscore
        schema_domains = YAML.load_file(schema_domain_file_path)

        domain_entry = Array(schema_domains[domain_key])
        if !domain_entry.include?(table_name)
          domain_entry << table_name
          schema_domains[domain_key] = domain_entry.sort
        end

        # make sure the output table is sorted
        schema_domains = schema_domains.sort_by { |key, _v| key }.to_h
        yaml = YAML.dump(schema_domains)

        # put the comment back
        yaml = yaml.gsub(/^---$/) { "# See https://thehub.github.com/engineering/development-and-ops/dotcom/schema-domains/." }
        File.open(schema_domain_file_path, "w+") { |f| f.write(yaml) }
      end

      def update_database_structure
        return if cluster == "mysql1"

        code = File.read(database_structure_file_path)

        source = RuboCop::ProcessedSource.new(code, RUBY_VERSION.to_f)

        rewriter = Parser::Source::TreeRewriter.new(source.buffer)
        const_name = "#{cluster.underscore.upcase}_TABLES"
        puts "Searching for constant #{const_name}..."
        node = source.ast.each_node.find do |node|
          node.type == :casgn && node.children[1].to_s == const_name
        end

        if node.nil?
          puts "Could not find constant #{const_name}"
          return
        end

        arr_node = node.children[2]
        percent_w_array = percent_w_array?(arr_node)

        result = arr_node.children.each_with_object({ added: false, last_node: nil }) do |n, acc|
          acc[:last_node] = n
          if n.value == table_name
            puts "Table #{table_name} already exists in #{const_name}"
            return
          end

          if n.value.casecmp(table_name) > 0
            acc[:added] = true
            if percent_w_array
              rewriter.insert_before(n.loc.expression, "#{table_name}\n      ")
            else
              rewriter.insert_before(n.loc.expression, "\"#{table_name}\",\n      ")
            end
            puts "Added #{table_name} to constant #{const_name}"
            break acc
          end
        end

        if !result[:added] && result[:last_node]
          if percent_w_array
            rewriter.insert_after(result[:last_node].loc.expression, "\n      #{table_name}")
          else
            rewriter.insert_after(result[:last_node].loc.expression, ",\n      \"#{table_name}\"")
          end
          puts "Added #{table_name} to constant #{const_name}"
        end

        File.open(database_structure_file_path, "w") { |f| f.write(rewriter.process) }
      end

      def update_tableowners
        tableowners_yaml = YAML.load_file(tableowners_file_path).to_h
        if tableowners_yaml.include?(table_name)
          puts "Table #{table_name} already has an owner"
        else
          tableowners_yaml[table_name] = owner
          tableowners_yaml = tableowners_yaml.sort_by { |key, _v| key }.to_h
          File.open(tableowners_file_path, "w") { |f| f.write(YAML.dump(tableowners_yaml)) }
          puts "Added table #{table_name} with owner #{owner} to #{tableowners_file_path}" # rubocop:disable GitHub/DoNotAllowLogin
        end
      end

      def percent_w_array?(node)
        node.source.start_with?("%w[")
      end
    end
  end
end
