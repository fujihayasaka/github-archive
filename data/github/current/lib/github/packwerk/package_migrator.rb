# typed: true
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "serviceowners"
require "yaml"

module GitHub
  module Packwerk
    class PackageMigrator

      VALID_PATH_PREFIXES = %w(app test packages).freeze

      def initialize(service_name: nil, package_name:, path_prefix:, dry_run: false)
        unless path_prefix.start_with?(*VALID_PATH_PREFIXES)
          raise "Unsupported path prefix '#{path_prefix}'. Manual migration may be necessary."
        end

        @path_prefix = path_prefix
        @service_name = service_name
        @package_name = package_name
        @dry_run = dry_run
      end

      # Moves files owned by services to packages/@package_name/
      def move_to_package
        create_package_config_file
        # Add @package_name as a dependency in the root package.yml file
        add_dependencies_for_package

        old_paths_and_specs = source_paths_and_specs
        update_package_files_serviceowner(old_paths_and_specs)

        # Remove package.yml and package_todo.yml files from the list
        # of files that need to be moved since those shouldn't be moved
        old_paths_and_specs.reject! { |path, _| File.fnmatch?("packages/*/{package,package_todo}.yml", path, File::FNM_EXTGLOB) }

        old_paths = old_paths_and_specs.keys
        new_paths = migrate_service_paths(old_paths)

        # Create pattern specs for the new file paths using the old pattern specs
        # in order to keep the review_groups information
        new_specs = new_paths.zip(old_paths_and_specs.values).map do |path, spec|
          ::Serviceowners::PatternSpec.new(path, spec.service, review_groups: spec.review_groups, no_reviews: spec.no_reviews?)
        end

        remove_from_serviceowners(old_paths)
        add_to_serviceowners(new_specs)
        remove_unmatched_serviceowner_patterns

        update_codeowners
        update_package_todo

        update_allowed_active_record_callbacks(old_paths, new_paths)
        update_cross_schema_domain_query_exemptions(old_paths, new_paths)
        update_api_serializer_helper_relative_requires(old_paths, new_paths)
        update_paths_in_rubocop_config(old_paths, new_paths)
        update_transaction_tracking_exemptions(old_paths, new_paths)
      end

      private

      DEFAULT_PACKAGE_CONFIG = <<~CONFIG
        enforce_dependencies: true
        enforce_privacy: false
        public_path: app/public

        dependencies:
        - "."
      CONFIG

      MIGRATED_SERVICES_FIXTURE_PATH = "test/fixtures/services_models_migrated_to_packages.txt"

      # Updates the service owner of package.yml and package_todo.yml files
      # if the service being migrated owns such files. These files should stay
      # with the package instead of being moves since they would overwrite the same
      # files in the target package.
      #
      # However, since we don't allow a service to have files across multiple packages,
      # we need to update the owner of those files to a different service in the same
      # source package from which that service is being migrated.
      def update_package_files_serviceowner(paths_and_specs)
        package_files = paths_and_specs.keys.select do |path|
          File.fnmatch?("packages/*/{package,package_todo}.yml", path, File::FNM_EXTGLOB)
        end

        # If the service doesn't own a package.yml or package_todo.yml
        # file, then there's nothing to do
        return if package_files.empty?

        # Get the name of the source package containing files owned by the
        # service being migrated. It's enough to use just one of these files
        # since Serviceowners already ensure that a service can't have files
        # across two or more packages
        source_package_name = File.basename(File.dirname(package_files.first))
        package_services = package_services(source_package_name) - services

        # Remove lines from SERVICEOWNERS which match these package.yml and
        # package_todo.yml files since we'll be adding new ones with the
        # new service owner
        remove_from_serviceowners(package_files)

        if package_services.empty?
          # If there are no other services in the source package, then it's safe
          # to delete these files as all the other files will be moved to a different
          # location
          package_files.each { |path| IO.popen(["git", "rm", "--quiet", path]).close }
        else
          # If there is at least one other service in the source package, pick
          # one service as the new owner of the package.yml and package_todo.yml
          # files, and add new lines to SERVICEOWNERS to make that change.
          new_owner_service = package_services.to_a.first
          new_paths_specs = package_files.map do |path|
            [path, ::Serviceowners::PatternSpec.new(path, new_owner_service)]
          end.to_h
          add_to_serviceowners(new_paths_specs.values)
        end
      end

      # Moves a list of files to new locations in target package directory and
      # returns a list of the new file paths
      def migrate_service_paths(paths)
        new_paths = paths.map { |path| new_path_for_file(path) }

        puts "Migrating paths..."

        paths.zip(new_paths).each { |old_path, new_path| migrate_path(old_path, new_path) }

        new_paths
      end

      # Determines the new path in packages/ for a file located at old_path
      # based on the target package name
      def new_path_for_file(old_path)
        if old_path.start_with?("packages")
          # For files that are already in a package, replace the old package
          # name with the new package name
          old_path_parts = Pathname.new(old_path).each_filename.to_a
          old_path_parts[1] = @package_name
          File.join(old_path_parts)
        else
          File.join("packages", @package_name, old_path)
        end
      end

      # Creates a packages/@package_name/package.yml file with default contents
      # unless the file already exists
      def create_package_config_file
        package_config_path = File.join("packages", @package_name, "package.yml")
        return if File.exist?(package_config_path)

        puts "Creating package config file #{package_config_path}..."
        return if @dry_run

        FileUtils.mkdir_p(File.join("packages", @package_name))
        File.open(package_config_path, "w") do |file|
          file.write(DEFAULT_PACKAGE_CONFIG)
        end
      end

      # Adds a list of packages as dependencies of another package. If target_package_name
      # is nil, then dependencies are added to the root package.yml file.
      def add_dependencies_for_package(new_dependencies: [@package_name], target_package_name: nil)
        package_config_path =
          if target_package_name
            File.join("packages", target_package_name, "package.yml")
          else
            "package.yml"
          end

        # Load the target package.yml file and fetch the list of existing dependencies
        package_config = YAML.safe_load_file(package_config_path)
        existing_dependencies = package_config["dependencies"] || []

        # Make sure all dependencies have the format: packages/PACKAGE_NAME
        new_dependencies.map! do |dependency|
          dependency.start_with?("packages") ? dependency : File.join("packages", dependency)
        end

        # Remove existing dependencies and the package itself from new dependencies
        # that will be added
        new_dependencies -= existing_dependencies
        new_dependencies -= [File.join("packages", target_package_name)] if target_package_name

        puts "Adding new dependencies in #{package_config_path}: #{new_dependencies.join(', ')}"
        return if @dry_run

        package_config["dependencies"] = existing_dependencies + new_dependencies

        File.write(package_config_path, package_config.to_yaml)
      end

      # Moves file at old_path to new_path and stages the change in Git
      # using git mv --force old_path new_path
      def migrate_path(old_path, new_path)
        puts "  #{old_path} -> #{new_path}"
        return if @dry_run

        FileUtils.mkpath(File.dirname(new_path))
        IO.popen(["git", "mv", "--force", old_path, new_path]).close
      end

      # Removes lines from SERVICEOWNERS file that have any file path from
      # paths argument as the prefix of the line, i.e. the pattern part.
      def remove_from_serviceowners(paths)
        lines = File.readlines("SERVICEOWNERS")

        puts "Removing lines from SERVICEOWNERS..."

        lines.each do |line|
          puts "  #{line}" if paths.any? { |path| line.include?(path) }
        end

        return if @dry_run

        File.open("SERVICEOWNERS", "w") do |file|
          lines.each do |line|
            file.write(line) unless paths.any? { |path| line.include?(path) }
          end
        end

        # reset serviceowners ivar in case file was changed
        @serviceowners = nil
      end

      # Appends lines to SERVICEOWNERS file based on a list of
      # Serviceowners::PatternSpec objects which include a path, service name,
      # and list of review groups
      def add_to_serviceowners(pattern_specs)
        puts "Adding lines to SERVICEOWNERS..."

        pattern_specs.each do |pattern_spec|
          puts "  #{pattern_spec.to_serviceowners}"
        end

        return if @dry_run

        lines = File.readlines("SERVICEOWNERS")

        File.open("SERVICEOWNERS", "a") do |file|
          pattern_specs.each { |pattern_spec| file.puts(pattern_spec.to_serviceowners) }
        end

        # reset serviceowners ivar in case file was changed
        @serviceowners = nil
      end

      # Finds and removes any unmatched patterns after making changes to
      # SERVICEOWNERS since such patterns are detected by the Serviceowners
      # gem and cause an exception.
      #
      # Unamtched patterns are patterns which don't match any files. This can
      # happen due to files being moved around by this script. For example,
      # if previously there was this in SERVICEOWNERS:
      #
      # app/models/foo/ :service1
      #
      # and there was only one file in app/models/foo/, then after moving
      # all service1 files to a package, the app/models/foo/ directory would
      # be empty and the app/models/foo/ pattern wouldn't match any files.
      def remove_unmatched_serviceowner_patterns
        unmatched_service_patterns = serviceowners.service_patterns.unmatched(serviceowners.file_index)

        puts "Removing unmatched service patterns from SERVICEOWNERS..."
        unmatched_service_patterns.each { |pattern_spec| puts "  #{pattern_spec.to_serviceowners}" }

        return if @dry_run

        # Get the text representation of all unmatched patterns
        unmatched_patterns = unmatched_service_patterns.map(&:pattern).map(&:text).to_set

        # Write the SERVICEOWNERS file again, but ship lines which use one of
        # the unmatched patterns for the service being migrated

        lines = File.readlines("SERVICEOWNERS")
        File.open("SERVICEOWNERS", "w") do |file|
          lines.each do |line|
            line_pattern, line_service = line_data(line)

            file.write(line) unless line_service && services.include?(line_service) && unmatched_patterns.include?(line_pattern)
          end
        end
      end

      # Runs bin/generate-service-files to update CODEOWNERS based on changes
      # in SERVICEOWNERS
      def update_codeowners
        puts "Updating serviceowners files..."
        return if @dry_run

        system("bin/generate-service-files.rb")
      end

      # Runs bin/packwerk update-todo to update the list of all cross-package
      # references/violations in package_todo.yml across all packages.
      #
      # Note: prior to running packwerk, we also remove all package_todo.yml
      # files since packwerk will not remove those files when all violations are
      # resolved. See https://github.com/Shopify/packwerk/issues/49 for details
      def update_package_todo
        puts "Updating package_todo.yml..."
        return if @dry_run

        `rm -f packages/*/package_todo.yml`
        system("bin/packwerk update-todo")
      end

      # Replaces strings from old_values list with strings in new_values list
      # in a text file at file_path
      def find_and_replace_in_file(old_values, new_values, file_path)
        file_text = File.read(file_path)

        puts "Replacing values in #{file_path}..."
        old_values.zip(new_values).each do |old_value, new_value|
          puts "  #{old_value} -> #{new_value}" if file_text.include?(old_value)
        end

        return if @dry_run

        old_values.zip(new_values).each { |old_value, new_value| file_text.gsub!(old_value, new_value) }
        File.open(file_path, "w") { |file| file.puts(file_text) }
      end

      # Updates any references to old file paths in with new file paths in
      # test/fixtures/allowed_active_record_callbacks.txt
      def update_allowed_active_record_callbacks(old_paths, new_paths)
        find_and_replace_in_file(old_paths, new_paths, "test/fixtures/allowed_active_record_callbacks.txt")
      end

      # Updates any references to old file paths in with new file paths in
      # test/fast/linting/cross_schema_domain_query_exemptions_test.rb
      def update_cross_schema_domain_query_exemptions(old_paths, new_paths)
        find_and_replace_in_file(old_paths, new_paths, "test/fast/linting/cross_schema_domain_query_exemptions_test.rb")
      end

      # Updates any references to old file paths with new file paths
      # in .rubocop.yml and .rubocop_todo.yml
      def update_paths_in_rubocop_config(old_paths, new_paths)
        find_and_replace_in_file(old_paths, new_paths, ".rubocop.yml")
        find_and_replace_in_file(old_paths, new_paths, ".rubocop_todo.yml")
      end

      # Updates any references to old file paths with new file paths
      # in config/transaction_tracking.yml
      def update_transaction_tracking_exemptions(old_paths, new_paths)
        find_and_replace_in_file(old_paths, new_paths, "config/transaction_tracking.yml")
      end

      # Replaces relative requires for API serializer helper with a regular require
      # since they would otherwise break when moving the file which contains the
      # relative require
      #
      # So, this:
      #
      # require_relative "../helper"
      #
      # is replaced with
      #
      # requre "models/api/helper"
      def update_api_serializer_helper_relative_requires(old_paths, new_paths)
        api_serializer_test_dir = File.join("test", "models", "api", "serializer")
        old_require_text = "require_relative \"../helper\""
        new_require_text = "require \"models/api/helper\""

        old_paths.zip(new_paths).each do |old_path, new_path|
          find_and_replace_in_file([old_require_text], [new_require_text], new_path) if File.dirname(old_path) == api_serializer_test_dir
        end
      end

      # Returns a Set containging the Symbol names of all services already in the given package, or just the
      # one service if a name is specified.
      def services
        return @services if defined?(@services)
        return @services = Set.new([@service_name.to_sym]) unless @service_name.nil?

        @services = package_services(@package_name)
      end

      # Returns a list of paths and their specs for any of the services under consideration that
      # reside in the file tree denoted by the provided path prefix.
      def source_paths_and_specs
        paths = serviceowners.paths.select { |path| path.start_with?(@path_prefix) }
        paths_and_specs = ::Serviceowners::PathData.new(paths, serviceowners.service_patterns).path_specs

        paths_and_specs.filter { |_path, spec| services.include?(spec&.service&.name) }
      end

      def line_data(line)
        line_pattern, line_service = line.split(":").map &:strip
        return nil unless line_service

        line_service = line_service.split(".").first&.to_sym
        [line_pattern, line_service] if line_service
      end

      # Determine the list of services which have files in the source package
      # except the service being migrated. To do this, we first fetch the list
      # of files and pattern specs in the source package, and then create a Set
      # of names of services for all those specs.
      def package_services(package_name)
        paths = serviceowners.paths.select { |path| path.start_with?("packages/#{@package_name}/") }
        pd = ::Serviceowners::PathData.new(paths, serviceowners.service_patterns)

        pd.path_specs.values.each_with_object(Set.new) do |spec, set|
          set.add(spec.service.name.to_sym) if spec&.service
        end
      end

      def serviceowners
        @serviceowners ||= ::Serviceowners::Main.new
      end
    end
  end
end
