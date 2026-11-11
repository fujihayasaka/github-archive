# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Updates app/actions/parse_config_file.rb with new package manager lookup
class EcosystemOnboarding
  class ParseConfigUpdater < BaseUpdater
    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      changes = []
      manual_steps = []

      parse_file = root_path.join("app/actions/parse_config_file.rb")
      return { changes: changes, manual_steps: manual_steps } unless File.exist?(parse_file)

      change_desc = "Add #{ecosystem_name} to PACKAGE_MANAGER_LOOKUP in parse_config_file.rb"
      return { changes: changes, manual_steps: manual_steps } unless should_proceed?(parse_file, change_desc)

      content = File.read(parse_file)

      return skip_if_exists(changes, manual_steps) if lookup_entry_exists?(content)

      modify_and_write_lookup(parse_file, content, changes)

      { changes: changes, manual_steps: manual_steps }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating parse_config_file.rb: #{e.message}" }
      { changes: [], manual_steps: [] }
    end

    private

    sig { params(content: String).returns(T::Boolean) }
    def lookup_entry_exists?(content)
      content.include?("\"#{ecosystem_name}\" =>")
    end

    sig do
      params(
        changes: T::Array[String],
        manual_steps: T::Array[String]
      ).returns(T::Hash[Symbol, T::Array[String]])
    end
    def skip_if_exists(changes, manual_steps)
      Rails.logger.debug { "⚠ #{ecosystem_name} already exists in PACKAGE_MANAGER_LOOKUP, skipping" }
      { changes: changes, manual_steps: manual_steps }
    end

    sig { returns(String) }
    def lookup_entry
      "\"#{ecosystem_name}\" => PackageManagers::#{package_manager_constant_name}"
    end

    sig { params(parse_file: Pathname, content: String, changes: T::Array[String]).void }
    def modify_and_write_lookup(parse_file, content, changes)
      modified_content = insert_into_lookup_hash(content)

      if modified_content == content
        Rails.logger.debug "✗ Could not find PACKAGE_MANAGER_LOOKUP hash"
      else
        write_and_log_changes(parse_file, modified_content, changes)
      end
    end

    sig { params(content: String).returns(String) }
    def insert_into_lookup_hash(content)
      content.sub(
        /(PACKAGE_MANAGER_LOOKUP\s*=\s*\{.*?)(\s+\}\.freeze)/m
      ) do
        hash_content = Regexp.last_match(1)
        closing = Regexp.last_match(2)

        "#{hash_content}\n    #{lookup_entry},#{closing}"
      end
    end

    sig { params(parse_file: Pathname, modified_content: String, changes: T::Array[String]).void }
    def write_and_log_changes(parse_file, modified_content, changes)
      File.write(parse_file, modified_content)
      changes << "Added #{lookup_entry} to PACKAGE_MANAGER_LOOKUP"
      Rails.logger.debug { "✓ Added #{ecosystem_name} to PACKAGE_MANAGER_LOOKUP" }
    end
  end
end
