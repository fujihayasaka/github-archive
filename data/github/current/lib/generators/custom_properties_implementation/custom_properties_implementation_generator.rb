# typed: true
# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "fileutils"

class CustomPropertiesImplementationGenerator < Rails::Generators::Base
  include Rails::Generators::Migration
  source_root File.expand_path("templates", __dir__)

  class_option :target_class, type: :string, desc: "Target class name for the custom property data (e.g., Repository, Organization)", required: true
  class_option :database_cluster, type: :string, desc: "Database cluster name (e.g., Repositories, Users, Main)", required: true
  class_option :package, type: :string, desc: "Packages folder name where the model should be placed", required: true
  class_option :skip_sorbet_rbi, type: :boolean, default: false, desc: "Skip generating Sorbet RBI files"
  class_option :skip_packwerk, type: :boolean, default: false, desc: "Skip updating Packwerk todo list"
  class_option :skip_migration, type: :boolean, default: false, desc: "Skip running database migrations"
  class_option :verbose, type: :boolean, default: false, desc: "Show verbose output from executed commands"

  # Accessor methods for required options
  sig { returns(String) }
  def target_class_name
    @target_class_name ||= options[:target_class].strip.camelize
  end

  sig { returns(String) }
  def database_cluster
    options[:database_cluster]
  end

  sig { returns(String) }
  def package_name
    @package_name ||= options[:package].strip.underscore
  end

  sig { void }
  def validate_arguments
    if target_class_name.blank?
      raise ArgumentError, "Target class name is required"
    end

    if database_cluster.blank?
      raise ArgumentError, "Database cluster name is required"
    end

    if package_name.blank?
      raise ArgumentError, "Package name is required"
    end

    unless valid_target_class?
      raise ArgumentError, "Invalid target class '#{target_class_name}'. Class does not exist or is not accessible."
    end

    unless package_exists?
      raise ArgumentError, "Package '#{package_name}' does not exist in packages/ directory"
    end

    unless package_models_directory_exists?
      raise ArgumentError, "Package '#{package_name}' does not have an app/models/ directory"
    end

    unless package_test_models_directory_exists?
      raise ArgumentError, "Package '#{package_name}' does not have a test/models/ directory"
    end

    # Validate database cluster early to avoid template generation failures
    validate_database_cluster!

    unless package_public_directory_exists?
      say "Creating public directory structure for #{package_name}...", :yellow
      create_package_public_directories
    end

    unless package_test_domain_directory_exists?
      say "Creating test domain directory structure for #{package_name}...", :yellow
      create_package_test_directories
    end

    unless package_has_database_dependency?
      say "Adding '#{expected_database_dependency}' to #{package_name} package.yml external_dependencies...", :yellow
      add_database_dependency_to_package
    end

    unless package_has_custom_properties_dependency?
      say "Adding '#{expected_custom_properties_dependency}' to #{package_name} package.yml dependencies...", :yellow
      add_custom_properties_dependency_to_package
    end
  end

  sig { void }
  def generate_model
    template "definition_model.rb.erb", "#{package_models_path}/#{target_class_name.underscore}_custom_property_definition.rb"
  end

  sig { void }
  def generate_value_model
    template "value_model.rb.erb", "#{package_models_path}/#{target_class_name.underscore}_custom_property_value.rb"
  end

  sig { void }
  def generate_custom_properties_dependency
    # Create the target class subdirectory if it doesn't exist
    target_class_subdir = "#{package_models_path}/#{target_class_name.underscore}"
    FileUtils.mkdir_p(target_class_subdir)

    template "custom_properties_dependency.rb.erb", "#{target_class_subdir}/custom_properties_dependency.rb"
  end

  sig { void }
  def generate_migration
    migration_template "definition_migration.rb.erb", "db/migrate/create_#{target_class_name.underscore}_custom_property_definitions.rb"
  end

  sig { void }
  def generate_value_migration
    migration_template "value_migration.rb.erb", "db/migrate/create_#{target_class_name.underscore}_custom_property_values.rb"
  end

  sig { void }
  def generate_definition_test
    template "definition_test.rb.erb", "#{package_test_models_path}/#{target_class_name.underscore}_custom_property_definition_test.rb"
  end

  sig { void }
  def generate_value_test
    template "value_test.rb.erb", "#{package_test_models_path}/#{target_class_name.underscore}_custom_property_value_test.rb"
  end

  sig { void }
  def generate_factories
    template "factories.rb.erb", "test/factories/#{target_class_name.underscore}_custom_properties_factories.rb"
  end

  sig { void }
  def generate_domain_accessor
    template "domain_accessor.rb.erb", "#{package_public_path}/#{package_name}/domain/custom_properties.rb"
  end

  sig { void }
  def update_or_create_domain_file
    domain_file_path = "#{package_public_path}/#{package_name}/domain.rb"
    accessor_line = "    accessor #{package_module_name}::Domain::CustomProperties"

    if File.exist?(domain_file_path)
      # Read the existing file to check if accessor already exists
      content = File.read(domain_file_path)

      # Check if the accessor line already exists
      if content.include?(accessor_line.strip)
        say "Custom properties accessor already exists in #{domain_file_path}", :blue
      else
        # Use Rails generator helper to insert the accessor after the class definition
        insert_into_file domain_file_path, "#{accessor_line}\n", after: /class Domain < GH::Domain::Base.*\n/
        say "Added custom properties accessor to existing #{domain_file_path}", :green
      end
    else
      # Create the domain.rb file from template
      template "domain.rb.erb", domain_file_path
      say "Created new domain file at #{domain_file_path}", :green
    end
  end

  sig { void }
  def generate_properties_config
    template "properties_config.rb.erb", "#{package_models_path}/#{target_class_name.underscore}_properties_config.rb"
  end

  sig { void }
  def update_or_create_domain_registration_file
    domain_registration_file_path = "#{package_public_path}/#{package_name}.rb"

    if File.exist?(domain_registration_file_path)
      content = File.read(domain_registration_file_path)

      # Check if the file already contains the required domain registration
      if content.include?("extend GH::Domain::Registration") && content.include?("register_domain #{package_module_name}::Domain")
        say "Domain registration already exists in #{domain_registration_file_path}", :blue
      else
        say "Warning: #{domain_registration_file_path} exists but doesn't contain proper domain registration", :yellow
        say "Please manually ensure it contains:", :yellow
        say "  extend GH::Domain::Registration", :yellow
        say "  register_domain #{package_module_name}::Domain", :yellow
      end
    else
      # Create the domain registration file from template
      template "domain_registration.rb.erb", domain_registration_file_path
      say "Created new domain registration file at #{domain_registration_file_path}", :green
    end
  end

  sig { void }
  def update_target_class_with_dependency
    target_class_file_path = "#{package_models_path}/#{target_class_name.underscore}.rb"
    comment_line = "  # TODO: Move this include line to an appropriate line if needed"
    include_line = "  include #{target_class_name}::CustomPropertiesDependency"

    if File.exist?(target_class_file_path)
      content = File.read(target_class_file_path)

      # Check if the include line already exists
      if content.include?(include_line.strip)
        say "CustomPropertiesDependency already included in #{target_class_file_path}", :blue
      else
        if content.match?(/class\s+#{target_class_name}/)
          insert_into_file target_class_file_path, "#{comment_line}\n#{include_line}\n", after: /class\s+#{target_class_name}.*\n/
          say "Added CustomPropertiesDependency include after class definition in #{target_class_file_path}", :green
        else
          say "Warning: Could not find appropriate location to add include in #{target_class_file_path}", :yellow
          say "Please manually add: #{include_line}", :yellow
        end
      end
    else
      say "Warning: Target class file #{target_class_file_path} does not exist", :yellow
      say "Please manually create the target class and add: #{include_line}", :yellow
    end
  end

  sig { void }
  def generate_domain_accessor_test
    template "domain_accessor_test.rb.erb", "#{package_test_path}/public/#{package_name}/domain/custom_properties_test.rb"
  end

  sig { void }
  def update_database_structure_tables
    database_structure_file_path = "lib/github/database_structure.rb"

    # Use Rails generator's file existence check with destination_root
    unless File.exist?(File.join(destination_root, database_structure_file_path))
      say "Warning: Could not find #{database_structure_file_path}. Skipping database structure update.", :yellow
      return
    end

    # Read the file content to perform checks before modification
    content = File.read(File.join(destination_root, database_structure_file_path))

    # Check if the database cluster constant exists
    database_cluster_tables_constant = "#{database_cluster.upcase}_TABLES"
    unless content.include?("#{database_cluster_tables_constant} = %w[")
      say "Database cluster '#{database_cluster}' (#{database_cluster_tables_constant}) not found in #{database_structure_file_path}. Skipping table additions.", :yellow
      return
    end

    # Check if tables are already present
    tables_to_add = [definition_table_name, value_table_name]
    tables_already_present = tables_to_add.all? { |table| content.include?(table) }

    if tables_already_present
      say "Tables #{tables_to_add.join(', ')} already exist in #{database_cluster_tables_constant}. Skipping.", :blue
      return
    end

    # Find the database cluster constant section and extract existing tables
    # Break down the complex regex into readable components
    escaped_constant = Regexp.escape(database_cluster_tables_constant)

    # Build regex to match the %w[] array format using named capture groups:
    # - Match the constant name and = %w[ opening with its indentation
    # - Capture the table names section (non-greedy)
    # - Capture the closing bracket indentation
    # Use word boundary and line start to ensure we match the complete constant definition
    indentation_pattern = '(?<indentation>[ \\t]+)'  # Only capture spaces/tabs, not newlines
    constant_declaration = "#{escaped_constant} = %w\\[\\s*\\n"
    tables_content = "(?<tables_section>.*?)"
    closing_pattern = '\\n(?<closing_indentation>\\s*)\\]'

    pattern = /^#{indentation_pattern}#{constant_declaration}#{tables_content}#{closing_pattern}/m

    match_data = content.match(pattern)
    return unless match_data

    # Extract named captures for better clarity
    indentation = match_data[:indentation]
    existing_tables_section = match_data[:tables_section]
    closing_indentation = match_data[:closing_indentation]
    return unless existing_tables_section

    # Parse existing tables (they are not quoted in %w[] arrays)
    # Filter out empty lines and normalize whitespace
    existing_tables = existing_tables_section.split(/\n/).map { |line| line.strip }.reject(&:empty?)

    # Add new tables and sort
    updated_tables = (existing_tables + tables_to_add).uniq.sort

    # Build the new tables section with proper indentation
    table_indentation = "#{indentation}  "
    new_tables_lines = updated_tables.map { |table| "#{table_indentation}#{table}" }.join("\n")
    new_section = "#{indentation}#{database_cluster_tables_constant} = %w[\n#{new_tables_lines}\n#{closing_indentation}]"

    # Use Rails generator gsub_file method to replace the section
    # This method automatically handles file paths relative to destination_root
    gsub_file database_structure_file_path, pattern, new_section

    say "Added tables #{tables_to_add.join(', ')} to #{database_cluster_tables_constant} in #{database_structure_file_path}", :green
  rescue StandardError => e
    say "Warning: Could not update #{database_structure_file_path}: #{e.message}. Skipping table additions.", :yellow
  end

  sig { void }
  def run_database_migrations
    unless options[:skip_migration]
      say "Running database migrations...", :green

      success = run "bin/rails db:migrate", capture: !options[:verbose]

      if success
        say "Database migrations completed successfully!", :green
      else
        say "Warning: Database migrations failed. You may need to run 'bin/rails db:migrate' manually.", :yellow
      end
    end
  end

  sig { void }
  def generate_sorbet_rbi_files
    unless options[:skip_sorbet_rbi]
      say "Generating Sorbet RBI files with bin/tapioca dsl...", :green
      say "Note: If this fails due to missing classes, run it manually after resolving the issues.", :yellow

      success = run "bin/tapioca dsl", capture: !options[:verbose]

      if success
        say "Sorbet RBI files generated successfully!", :green
      else
        say "Warning: Failed to generate Sorbet RBI files. You may need to run 'bin/tapioca dsl' manually after resolving failures.", :yellow
      end
    end
  end

  sig { void }
  def update_packwerk_todo
    unless options[:skip_packwerk]
      say "Updating Packwerk todo list...", :green
      packwerk_success = run "bin/packwerk update-todo", capture: !options[:verbose]

      if packwerk_success
        say "Packwerk todo list updated successfully!", :green
      else
        say "Warning: Failed to update Packwerk todo list. You may need to run 'bin/packwerk update-todo' manually.", :yellow
      end
    end
  end

  sig { params(dirname: String).returns(String) }
  def self.next_migration_number(dirname)
    @migration_number ||= Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
    @migration_number += 1
    @migration_number.to_s
  end

  private

  sig { void }
  def validate_database_cluster!
    # This will trigger the memoized application_record_domain method
    # which will raise an error if the database cluster is invalid
    application_record_domain
  end

  sig { returns(String) }
  def find_application_record_domain
    # Try different capitalization patterns for the database cluster
    cluster_variations = [
      database_cluster.camelize,           # users -> Users
      database_cluster.downcase,           # Users -> users
      database_cluster                     # as provided
    ].uniq

    cluster_variations.each do |cluster_name|
      # Check if there's a Domain class for this cluster
      domain_class_name = "ApplicationRecord::Domain::#{cluster_name}"
      fallback_class_name = "ApplicationRecord::#{cluster_name}"

      # Try Domain class first, then fallback class
      [domain_class_name, fallback_class_name].each do |class_name|
        begin
          class_name.constantize
          return class_name
        rescue NameError
          # Continue to next option
        end
      end
    end

    # If we get here, no valid class exists
    raise ArgumentError, <<~ERROR
      Invalid database cluster '#{database_cluster}'.
      Could not find a valid ApplicationRecord class for this cluster.

      Tried the following class names:
      #{cluster_variations.flat_map { |v| ["  ApplicationRecord::Domain::#{v}", "  ApplicationRecord::#{v}"] }.join("\n")}

      See lib/application_record/ for available cluster classes.
    ERROR
  end

  sig { returns(String) }
  def definition_class_name
    "#{target_class_name}CustomPropertyDefinition"
  end

  sig { returns(String) }
  def value_class_name
    "#{target_class_name}CustomPropertyValue"
  end

  sig { returns(String) }
  def definition_table_name
    "#{target_class_name.underscore}_custom_property_definitions"
  end

  sig { returns(String) }
  def definition_migration_class_name
    "Create#{target_class_name}CustomPropertyDefinitions"
  end

  sig { returns(String) }
  def value_table_name
    "#{target_class_name.underscore}_custom_property_values"
  end

  sig { returns(String) }
  def value_migration_class_name
    "Create#{target_class_name}CustomPropertyValues"
  end

  sig { returns(String) }
  def value_test_class_name
    "#{target_class_name}CustomPropertyValueTest"
  end

  sig { returns(String) }
  def definition_test_class_name
    "#{target_class_name}CustomPropertyDefinitionTest"
  end

  sig { returns(String) }
  def properties_config_class_name
    "#{target_class_name}PropertiesConfig"
  end

  sig { returns(String) }
  def package_module_name
    package_name.camelize
  end

  sig { returns(String) }
  def application_record_domain
    @application_record_domain ||= find_application_record_domain
  end

  sig { returns(T::Boolean) }
  def package_exists?
    File.directory?(package_path)
  end

  sig { returns(T::Boolean) }
  def valid_target_class?
    begin
      target_class_name.constantize
      true
    rescue NameError
      false
    end
  end

  sig { returns(T::Boolean) }
  def package_models_directory_exists?
    File.directory?(package_models_path)
  end

  sig { returns(T::Boolean) }
  def package_test_models_directory_exists?
    File.directory?(package_test_models_path)
  end

  sig { returns(T::Boolean) }
  def package_public_directory_exists?
    File.directory?("#{package_public_path}/#{package_name}/domain")
  end

  sig { void }
  def create_package_public_directories
    FileUtils.mkdir_p("#{package_public_path}/#{package_name}/domain")
  end

  sig { returns(T::Boolean) }
  def package_test_domain_directory_exists?
    File.directory?("#{package_test_path}/public/#{package_name}/domain")
  end

  sig { void }
  def create_package_test_directories
    FileUtils.mkdir_p("#{package_test_path}/public/#{package_name}/domain")
  end

  sig { returns(String) }
  def package_path
    File.join(base_path, "packages", package_name)
  end

  sig { returns(String) }
  def package_models_path
    "#{package_path}/app/models"
  end

  sig { returns(String) }
  def package_test_models_path
    "#{package_path}/test/models"
  end

  sig { returns(String) }
  def package_public_path
    "#{package_path}/app/public"
  end

  sig { returns(String) }
  def package_test_path
    "#{package_path}/test"
  end

  sig { returns(String) }
  def base_path
    # Use destination_root during testing, otherwise use current directory
    respond_to?(:destination_root) ? destination_root : "."
  end

  sig { returns(T::Boolean) }
  def package_has_database_dependency?
    return false unless package_yml_exists?

    package_config = load_package_yml
    external_deps = package_config.dig("metadata", "external_dependencies") || []
    external_deps.include?(expected_database_dependency)
  end

  sig { returns(T::Boolean) }
  def package_has_custom_properties_dependency?
    return false unless package_yml_exists?

    package_config = load_package_yml
    dependencies = package_config["dependencies"] || []
    dependencies.include?(expected_custom_properties_dependency)
  end

  sig { returns(T::Boolean) }
  def package_yml_exists?
    File.exist?(package_yml_path)
  end

  sig { returns(String) }
  def package_yml_path
    "#{package_path}/package.yml"
  end

  sig { returns(String) }
  def expected_database_dependency
    "mysql/#{database_cluster.underscore}"
  end

  sig { returns(String) }
  def expected_custom_properties_dependency
    "packages/custom_properties"
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def load_package_yml
    require "yaml"
    YAML.safe_load_file(package_yml_path) || {}
  end

  sig { void }
  def add_database_dependency_to_package
    package_config = load_package_yml

    # Ensure the metadata section exists
    package_config["metadata"] ||= {}

    # Ensure the external_dependencies section exists
    package_config["metadata"]["external_dependencies"] ||= []

    # Add the dependency if it doesn't already exist
    external_deps = package_config["metadata"]["external_dependencies"]
    unless external_deps.include?(expected_database_dependency)
      external_deps << expected_database_dependency
      external_deps.sort!

      # Write the updated config back to the file
      File.open(package_yml_path, "w") do |file|
        file.write(YAML.dump(package_config))
      end

      say "Added '#{expected_database_dependency}' to #{package_yml_path}", :green
    end
  end

  sig { void }
  def add_custom_properties_dependency_to_package
    package_config = load_package_yml

    # Ensure the dependencies section exists
    package_config["dependencies"] ||= []

    # Add the dependency if it doesn't already exist
    dependencies = package_config["dependencies"]
    unless dependencies.include?(expected_custom_properties_dependency)
      dependencies << expected_custom_properties_dependency
      dependencies.sort!

      # Write the updated config back to the file
      File.open(package_yml_path, "w") do |file|
        file.write(YAML.dump(package_config))
      end

      say "Added '#{expected_custom_properties_dependency}' to #{package_yml_path}", :green
    end
  end
end
