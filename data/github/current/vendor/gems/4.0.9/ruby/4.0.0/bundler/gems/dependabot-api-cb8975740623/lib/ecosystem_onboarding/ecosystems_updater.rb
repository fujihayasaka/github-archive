# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Updates lib/ecosystems.rb with new package manager definitions
class EcosystemOnboarding
  class EcosystemsUpdater < BaseUpdater
    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      changes = []
      manual_steps = []

      ecosystems_file = root_path.join("lib/ecosystems.rb")
      return { changes: changes, manual_steps: manual_steps } unless File.exist?(ecosystems_file)

      content = File.read(ecosystems_file)
      original_content = content.dup

      # Chain transformations
      content = process_beta_array(ecosystems_file, content, changes)
      content = process_package_managers(ecosystems_file, content, changes)
      content = process_language_mapping(ecosystems_file, content, changes, manual_steps)

      # Write all changes at once if content was modified
      File.write(ecosystems_file, content) if content != original_content

      { changes: changes, manual_steps: manual_steps }
    end

    private

    # Helper methods for processing transformations and extracting results
    sig { params(ecosystems_file: Pathname, content: String, changes: T::Array[String]).returns(String) }
    def process_beta_array(ecosystems_file, content, changes)
      result = add_to_beta_array(ecosystems_file, content)
      changes.concat(T.cast(result[:changes], T::Array[String]))
      T.cast(result[:content], String)
    end

    sig { params(ecosystems_file: Pathname, content: String, changes: T::Array[String]).returns(String) }
    def process_package_managers(ecosystems_file, content, changes)
      result = add_to_package_managers_list(ecosystems_file, content)
      changes.concat(T.cast(result[:changes], T::Array[String]))
      T.cast(result[:content], String)
    end

    sig do
      params(
        ecosystems_file: Pathname,
        content: String,
        changes: T::Array[String],
        manual_steps: T::Array[String]
      ).returns(String)
    end
    def process_language_mapping(ecosystems_file, content, changes, manual_steps)
      result = add_to_language_mapping(ecosystems_file, content)
      changes.concat(T.cast(result[:changes], T::Array[String]))
      manual_steps.concat(T.cast(result[:manual_steps], T::Array[String]))
      T.cast(result[:content], String)
    end

    sig { params(ecosystems_file: Pathname, content: String).returns(T::Hash[Symbol, T.any(T::Array[String], String)]) }
    def add_to_beta_array(ecosystems_file, content)
      changes = T.let([], T::Array[String])

      change_desc = "Add #{package_manager_constant_name} to Ecosystems::BETA array"
      return { changes: changes, content: content } unless should_proceed?(ecosystems_file, change_desc)

      constant_ref = "PackageManagers::#{package_manager_constant_name}"

      return { changes: changes, content: content } if beta_array_includes?(content, constant_ref)

      modified_content = insert_into_beta_array(content, constant_ref)
      if modified_content == content
        Rails.logger.debug { "✗ Could not find BETA array in ecosystems.rb" }
      else
        changes << "Added #{constant_ref} to Ecosystems::BETA array"
        Rails.logger.debug { "✓ Added #{constant_ref} to BETA array" }
      end

      { changes: changes, content: modified_content }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating BETA array: #{e.message}" }
      { changes: changes, content: content }
    end

    sig { params(ecosystems_file: Pathname, content: String).returns(T::Hash[Symbol, T.any(T::Array[String], String)]) }
    def add_to_package_managers_list(ecosystems_file, content)
      changes = T.let([], T::Array[String])

      change_desc = "Add #{package_manager_constant_name} to PackageManagers::ALL"
      return { changes: changes, content: content } unless should_proceed?(ecosystems_file, change_desc)

      constant_def = "#{package_manager_constant_name} = \"#{package_manager_name}\""

      return { changes: changes, content: content } if package_managers_includes?(content, constant_def)

      modified_content = insert_into_package_managers(content, constant_def)
      if modified_content == content
        Rails.logger.debug { "✗ Could not find PackageManagers::ALL array" }
      else
        changes << "Added #{constant_def} to PackageManagers::ALL"
        Rails.logger.debug { "✓ Added #{constant_def} to PackageManagers::ALL" }
      end

      { changes: changes, content: modified_content }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating PackageManagers list: #{e.message}" }
      { changes: changes, content: content }
    end

    sig { params(content: String, constant_ref: String).returns(T::Boolean) }
    def beta_array_includes?(content, constant_ref)
      beta_match = content.match(/BETA\s*=\s*\[(.*?)\]/m)
      if beta_match && T.must(beta_match[1]).include?(constant_ref)
        Rails.logger.debug { "⚠ #{constant_ref} already exists in BETA array, skipping" }
        return true
      end
      false
    end

    sig { params(content: String, constant_ref: String).returns(String) }
    def insert_into_beta_array(content, constant_ref)
      # Extract existing array contents
      beta_match = content.match(/BETA\s*=\s*\[(.*?)\]\.freeze/m)
      return content unless beta_match

      existing_entries = T.must(beta_match[1]).
                         scan(/PackageManagers::\w+/)

      # Add new entry and sort alphabetically
      all_entries = (existing_entries + [constant_ref]).uniq.sort

      # Build the new array with proper formatting
      if all_entries.empty?
        new_array = "BETA = [\n  ].freeze"
      else
        formatted_entries = all_entries.map { |entry| "    #{entry}," }.join("\n")
        new_array = "BETA = [\n#{formatted_entries}\n  ].freeze"
      end

      # Replace the entire BETA array
      content.sub(/BETA\s*=\s*\[.*?\]\.freeze/m, new_array)
    end

    sig { params(content: String, constant_def: String).returns(T::Boolean) }
    def package_managers_includes?(content, constant_def)
      if content.include?(constant_def)
        Rails.logger.debug { "⚠ #{constant_def} already exists in PackageManagers, skipping" }
        return true
      end
      false
    end

    sig { params(content: String, constant_def: String).returns(String) }
    def insert_into_package_managers(content, constant_def)
      # Extract existing array contents
      pm_match = content.match(/module\s+PackageManagers\s+ALL\s*=\s*\[(.*?)\]\.freeze/m)
      return content unless pm_match

      # Parse existing entries (format: "CONSTANT = "value"")
      existing_entries = T.must(pm_match[1]).
                         scan(/(\w+)\s*=\s*"([^"]+)"/).
                         map { |constant, value| "#{constant} = \"#{value}\"" }

      # Add new entry and sort alphabetically
      all_entries = (existing_entries + [constant_def]).uniq.sort

      # Build the new array with proper formatting
      if all_entries.empty?
        new_array = "module PackageManagers\n  ALL = [\n  ].freeze"
      else
        formatted_entries = all_entries.map { |entry| "    #{entry}," }.join("\n")
        new_array = "module PackageManagers\n  ALL = [\n#{formatted_entries}\n  ].freeze"
      end

      # Replace the entire PackageManagers::ALL array
      content.sub(/module\s+PackageManagers\s+ALL\s*=\s*\[.*?\]\.freeze/m, new_array)
    end

    sig do
      params(
        ecosystems_file: Pathname,
        content: String
      ).returns(T::Hash[Symbol, T.any(T::Array[String], String)])
    end
    def add_to_language_mapping(ecosystems_file, content)
      changes = T.let([], T::Array[String])
      manual_steps = T.let([], T::Array[String])

      change_desc = "Add #{package_manager_constant_name} to PACKAGE_MANAGER_LANGUAGE_MAPPING"
      unless should_proceed?(ecosystems_file, change_desc)
        return { changes: changes, manual_steps: manual_steps, content: content }
      end

      constant_ref = "PackageManagers::#{package_manager_constant_name}"
      if language_mapping_includes?(content, constant_ref)
        return { changes: changes, manual_steps: manual_steps, content: content }
      end

      modified_content = apply_language_mapping_update(content, constant_ref, changes)
      manual_steps << build_language_mapping_manual_step(constant_ref)

      { changes: changes, manual_steps: manual_steps, content: modified_content }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating PACKAGE_MANAGER_LANGUAGE_MAPPING: #{e.message}" }
      { changes: changes, manual_steps: manual_steps, content: content }
    end

    sig { params(constant_ref: String).returns(String) }
    def build_language_mapping_manual_step(constant_ref)
      "Update PACKAGE_MANAGER_LANGUAGE_MAPPING in lib/ecosystems.rb to map #{constant_ref} to the " \
        "appropriate language from Languages module"
    end

    sig { params(content: String, constant_ref: String, changes: T::Array[String]).returns(String) }
    def apply_language_mapping_update(content, constant_ref, changes)
      modified_content = insert_into_language_mapping(content, constant_ref)
      if modified_content == content
        Rails.logger.debug { "✗ Could not find PACKAGE_MANAGER_LANGUAGE_MAPPING" }
      else
        changes << "Added #{constant_ref} to PACKAGE_MANAGER_LANGUAGE_MAPPING with TODO comment"
        Rails.logger.debug { "✓ Added #{constant_ref} to PACKAGE_MANAGER_LANGUAGE_MAPPING with TODO" }
      end
      modified_content
    end

    sig { params(content: String, constant_ref: String).returns(T::Boolean) }
    def language_mapping_includes?(content, constant_ref)
      mapping_match = content.match(/PACKAGE_MANAGER_LANGUAGE_MAPPING\s*=\s*\{(.*?)\}\.freeze/m)
      if mapping_match && T.must(mapping_match[1]).include?(constant_ref)
        Rails.logger.debug { "⚠ #{constant_ref} already exists in PACKAGE_MANAGER_LANGUAGE_MAPPING, skipping" }
        return true
      end
      false
    end

    sig { params(content: String, constant_ref: String).returns(String) }
    def insert_into_language_mapping(content, constant_ref)
      # Extract existing mapping contents
      mapping_match = content.match(/PACKAGE_MANAGER_LANGUAGE_MAPPING\s*=\s*\{(.*?)\}\.freeze/m)
      return content unless mapping_match

      # Parse existing entries (format: "PackageManagers::CONSTANT => Languages::LANG")
      existing_entries = T.must(mapping_match[1]).
                         scan(/PackageManagers::(\w+)\s*=>\s*Languages::(\w+)/).
                         map { |pm, lang| "PackageManagers::#{pm} => Languages::#{lang}" }

      # Add new entry with nil placeholder and sort alphabetically
      new_entry = "#{constant_ref} => nil, # TODO: map to a new or existing language from `Languages`"
      all_entries = (existing_entries + [new_entry]).uniq.sort

      # Build the new mapping with proper formatting
      if all_entries.empty?
        new_mapping = "PACKAGE_MANAGER_LANGUAGE_MAPPING = {\n  }.freeze"
      else
        formatted_entries = all_entries.map { |entry| "    #{entry}," }.join("\n")
        new_mapping = "PACKAGE_MANAGER_LANGUAGE_MAPPING = {\n#{formatted_entries}\n  }.freeze"
      end

      # Replace the entire PACKAGE_MANAGER_LANGUAGE_MAPPING
      content.sub(/PACKAGE_MANAGER_LANGUAGE_MAPPING\s*=\s*\{.*?\}\.freeze/m, new_mapping)
    end
  end
end
