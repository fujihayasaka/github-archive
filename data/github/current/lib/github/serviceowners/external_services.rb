# typed: strict
# frozen_string_literal: true

module GitHub
  class Serviceowners
    class ExternalServices
      extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

      PACKAGE_CONFIG_FILENAME = "package.yml"
      DOMAIN_FILE_GLOB = T.let(File.join("lib", "application_record", "domain", "*").to_s.freeze, String)

      # Some active record bases for clusters map to non-standard cluster names.
      # These names have been defined in the `cluster_name` class methods of the affected classes
      # but as this cop is run outside of the Rails environment, we need to define them here.
      CLUSTER_SERVICE_OVERRIDES = T.let({
          "Migrations" => "mysql/octoshift",
          "TokenScanningService" => "mysql/token-scanning-service-prod",
          "NotificationsEntries" => "mysql/notifications_entries",
          "IamAbilities" => "mysql/iam_abilities",
          "Memex" => "mysql/blanket",
          "Iam" => "mysql/collab",
        },
        T::Hash[String, String]
      )

      # Let's verify that we found a reasonable number of mappings. This should cause the cop
      # to blow up if someone moves the domain records or changes how they are written.
      MAPPINGS_SANITY_COUNT = T.let(90, Integer)

      MYSQL_DOMAIN_MATCHER = T.let(/^\s*class (?<domain_constant>[\w]+) < ApplicationRecord::(?<cluster_constant>.+)\s*$/,
        Regexp)

      sig { void }
      def initialize
        @root_path = T.let(Dir.pwd + "/", String)
        @constant_dependencies = T.let(constant_mappings, T::Hash[String, String])
        @package_paths = T.let(nil, T.nilable(T::Array[String]))
        @dependencies = T.let({}, T::Hash[String, T::Array[String]])
      end

      sig { params(dependency: String, path: String).returns(T::Boolean) }
      def dependency_declared?(dependency, path)
        file_path = package_config_path(path)
        return false unless file_path

        !!dependencies_for_package_config(file_path).include?(dependency)
      end

      sig { params(path: String).returns(T::Array[String]) }
      def dependencies_for_package_config(path)
        @dependencies[path] ||= load_dependencies(path)
      end

      sig { params(constant_name: String).returns(T.nilable(String)) }
      def external_dependency_for(constant_name)
        constant_name = constant_name.delete_prefix("::")
        @constant_dependencies[constant_name]
      end

      sig { params(path: String).returns(T.nilable(String)) }
      def package_config_path(path)
        path = path.delete_prefix(@root_path)
        package_dir = package_paths.detect do |package_path|
          path.start_with?(package_path)
        end
        return unless package_dir
        File.join(package_dir, PACKAGE_CONFIG_FILENAME)
      end

      private

      sig { params(path: String).returns(T::Array[String]) }
      def load_dependencies(path)
        package_config = YAML.safe_load_file(path, symbolize_names: true)
        package_config.dig(:metadata, :external_dependencies) || []
      end

      sig { returns(T::Array[String]) }
      def package_paths
        @package_paths ||= find_package_paths(@root_path)
      end

      sig { returns(T::Hash[String, String]) }
      def constant_mappings
        glob = File.join(@root_path, DOMAIN_FILE_GLOB)
        mappings = Hash.new.tap do |mappings|
          Dir[glob].each { |path| update_mappings_for_path(path, mappings) }
        end

        if mappings.count < MAPPINGS_SANITY_COUNT
          raise "It appears there are not as many schema domain constants as expected. Have changes been made to files in `#{glob}`?"
        end

        mappings
      end

      sig { params(root_path: String).returns(T::Array[String]) }
      def find_package_paths(root_path)
        glob_pattern = File.join(root_path, "**", PACKAGE_CONFIG_FILENAME)
        vendored_gems_path = File.join(root_path, "vendor/gems")

        package_paths = Dir[glob_pattern].reject { |path| path.start_with?(vendored_gems_path) }

        chomp_path = "/#{PACKAGE_CONFIG_FILENAME}"
        package_paths.each do |file_path|
          file_path.delete_prefix!(root_path)
          file_path.chomp!(chomp_path)
        end

        package_paths.reverse
      end

      sig { params(path: String, mappings: T::Hash[String, String]).void }
      def update_mappings_for_path(path, mappings)
        return unless File.file?(path)

        contents = File.read(path)
        match = contents.match(MYSQL_DOMAIN_MATCHER)

        return if match.nil?
        cluster_constant = match[:cluster_constant]
        domain_constant = match[:domain_constant]

        return if cluster_constant.nil? || domain_constant.nil?

        update_mappings_for_constants(cluster_constant, domain_constant, mappings)
      end

      sig { params(cluster_constant: String, domain_constant: String, mappings: T::Hash[String, String]).void }
      def update_mappings_for_constants(cluster_constant, domain_constant, mappings)
        service_name = service_name_for_constant(cluster_constant)

        mappings["ApplicationRecord::#{cluster_constant}"] = service_name
        mappings["ApplicationRecord::Domain::#{domain_constant}"] = service_name
      end

      sig { params(constant_name: String).returns(String) }
      def service_name_for_constant(constant_name)
        constant_name = constant_name.delete_prefix("::")
        CLUSTER_SERVICE_OVERRIDES[constant_name] || "mysql/#{constant_name.underscore.dasherize}"
      end
    end
  end
end
