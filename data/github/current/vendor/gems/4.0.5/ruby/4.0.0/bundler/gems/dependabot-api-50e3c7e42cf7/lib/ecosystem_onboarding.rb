# typed: strong
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "sorbet-runtime"
require_relative "ecosystem_onboarding/base_updater"
require_relative "ecosystem_onboarding/protobuf_updater"
require_relative "ecosystem_onboarding/ecosystems_updater"
require_relative "ecosystem_onboarding/file_regex_updater"
require_relative "ecosystem_onboarding/parse_config_updater"
require_relative "ecosystem_onboarding/json_schema_updater"

# Handles onboarding a new ecosystem by automating repetitive file changes
class EcosystemOnboarding
  extend T::Sig

  sig { returns(String) }
  attr_reader :ecosystem_name

  sig { returns(String) }
  attr_reader :package_manager_name

  sig { returns(String) }
  attr_reader :mode

  sig { returns(T::Array[String]) }
  attr_reader :changes_made

  sig { returns(T::Array[String]) }
  attr_reader :manual_steps

  sig do
    params(
      ecosystem_name: T.any(String, Symbol),
      package_manager_name: T.nilable(T.any(String, Symbol)),
      mode: T.any(String, Symbol)
    ).void
  end
  def initialize(ecosystem_name:, package_manager_name: nil, mode: "interactive")
    @ecosystem_name = T.let(ecosystem_name.to_s.downcase, String)
    @package_manager_name = T.let((package_manager_name || ecosystem_name).to_s.downcase, String)
    @mode = T.let(mode.to_s.downcase, String)
    @changes_made = T.let([], T::Array[String])
    @manual_steps = T.let([], T::Array[String])
    @root_path = T.let(nil, T.nilable(Pathname))

    validate_mode!
  end

  sig { void }
  def run
    Rails.logger.debug "\n=== Ecosystem Onboarding Tool ==="
    Rails.logger.debug { "Ecosystem: #{ecosystem_name}" }
    Rails.logger.debug { "Package Manager: #{package_manager_name}" }
    Rails.logger.debug { "Mode: #{mode}" }
    Rails.logger.debug "=" * 50

    # Run all updaters in sequence
    run_updater(ProtobufUpdater)
    run_updater(EcosystemsUpdater)
    run_updater(FileRegexUpdater)
    run_updater(ParseConfigUpdater)
    run_updater(JsonSchemaUpdater)

    # Output summary
    print_summary

    Rails.logger.debug "\n✓ Onboarding complete!"
  end

  private

  sig { params(updater_class: T.class_of(BaseUpdater)).void }
  def run_updater(updater_class)
    updater = updater_class.new(
      ecosystem_name: ecosystem_name,
      package_manager_name: package_manager_name,
      root_path: root_path,
      mode: mode
    )

    result = updater.update
    @changes_made.concat(T.must(result[:changes]))
    @manual_steps.concat(T.must(result[:manual_steps]))
  end

  sig { returns(Pathname) }
  def root_path
    @root_path ||= if defined?(Rails)
                     Rails.root
                   else
                     # When not in Rails context, find the root by looking for characteristic files
                     current_dir = Pathname.new(__FILE__).expand_path.dirname
                     until current_dir.to_s == "/" || current_dir.join("Gemfile").exist?
                       current_dir = current_dir.parent
                     end
                     current_dir
                   end
  end

  sig { void }
  def validate_mode!
    valid_modes = %w(interactive skip overwrite)
    return if valid_modes.include?(mode)

    raise ArgumentError, "Invalid mode: #{mode}. Must be one of: #{valid_modes.join(', ')}"
  end

  sig { void }
  def print_summary
    Rails.logger.debug "\n" + ("=" * 50)
    Rails.logger.debug "SUMMARY"
    Rails.logger.debug "=" * 50

    if changes_made.any?
      Rails.logger.debug "\n✓ Changes made:"
      changes_made.each do |change|
        Rails.logger.debug "  - #{change}"
      end
    else
      Rails.logger.debug "\nℹ No changes were made"
    end

    if manual_steps.any?
      Rails.logger.debug "\n⚠ Manual steps required:"
      manual_steps.each_with_index do |step, index|
        Rails.logger.debug "  #{index + 1}. #{step}"
      end
    end

    print_additional_notes
  end

  sig { void }
  def print_additional_notes
    Rails.logger.debug "\n📝 Additional notes:"
    Rails.logger.debug "  - Review all TODO comments in the generated code"
    Rails.logger.debug { "  - Update file patterns in EcosystemFileRegex##{package_manager_name.tr('-', '_')}_regex" }
    Rails.logger.debug "  - Add language mapping to Ecosystems::PACKAGE_MANAGER_LANGUAGE_MAPPING if needed"
    Rails.logger.debug "  - Add advisorydb mapping to Advisorydb::PACKAGE_MANAGERS if applicable"
    Rails.logger.debug "  - Run tests to ensure everything works correctly"
    Rails.logger.debug "  - Check and update documentation as needed."
    Rails.logger.debug "\n📚 See Dependabot Version Updates: Adding a new Ecosystem"
    Rails.logger.debug "  - https://github.com/github/dependabot-updates/blob/main/docs/development/version-updates/adding-a-new-ecosystem.md"
  end
end
