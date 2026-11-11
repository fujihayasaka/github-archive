# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Updates lib/ecosystem_file_regex.rb with new regex methods
class EcosystemOnboarding
  class FileRegexUpdater < BaseUpdater
    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      changes = []
      manual_steps = []

      regex_file = root_path.join("lib/ecosystem_file_regex.rb")
      return { changes: changes, manual_steps: manual_steps } unless File.exist?(regex_file)

      change_desc = "Add #{package_manager_name}_regex method to EcosystemFileRegex"
      return { changes: changes, manual_steps: manual_steps } unless should_proceed?(regex_file, change_desc)

      content = File.read(regex_file)
      method_name = "#{package_manager_name.tr('-', '_')}_regex"

      return skip_if_exists(method_name, changes, manual_steps) if method_already_exists?(content, method_name)

      insert_and_log_regex_method(regex_file, content, method_name, changes)

      { changes: changes, manual_steps: manual_steps }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error adding ecosystem file regex: #{e.message}" }
      { changes: [], manual_steps: [] }
    end

    private

    sig { params(content: String, method_name: String).returns(T::Boolean) }
    def method_already_exists?(content, method_name)
      content.include?("def #{method_name}")
    end

    sig do
      params(
        method_name: String,
        changes: T::Array[String],
        manual_steps: T::Array[String]
      ).returns(T::Hash[Symbol, T::Array[String]])
    end
    def skip_if_exists(method_name, changes, manual_steps)
      Rails.logger.debug { "⚠ #{method_name} method already exists, skipping" }
      { changes: changes, manual_steps: manual_steps }
    end

    sig do
      params(
        regex_file: Pathname,
        content: String,
        method_name: String,
        changes: T::Array[String]
      ).void
    end
    def insert_and_log_regex_method(regex_file, content, method_name, changes)
      if insert_regex_method(regex_file, content, method_name)
        changes << "Added #{method_name} method to EcosystemFileRegex (TODO: add correct patterns)"
        Rails.logger.debug { "✓ Added #{method_name} method (requires manual TODO completion)" }
      else
        Rails.logger.debug "✗ Could not find insertion point for regex method"
      end
    end

    sig { params(regex_file: Pathname, content: String, method_name: String).returns(T::Boolean) }
    def insert_regex_method(regex_file, content, method_name)
      # Find the last method definition before "end" of the class
      insertion_point = content.rindex(/^  def \w+_regex.*?^  end/m)
      return false unless insertion_point

      # Find the end of the last method
      match = T.must(content[insertion_point..]).match(/^  end/)
      return false unless match

      position = insertion_point + match.end(0)

      new_method = build_regex_method(method_name)
      modified_content = T.must(content[0...position]) + new_method + T.must(content[position..])

      File.write(regex_file, modified_content)
      true
    end

    sig { params(method_name: String).returns(String) }
    def build_regex_method(method_name)
      "\n\n  " \
        "def #{method_name}\n    " \
        "[\n      " \
        "# TODO: Add the correct file patterns for #{package_manager_name}\n      " \
        "# Example: /^package\\.json$/, /^package-lock\\.json$/\n    " \
        "]\n  " \
        "end"
    end
  end
end
