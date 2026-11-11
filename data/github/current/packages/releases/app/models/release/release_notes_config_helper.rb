# typed: true
# frozen_string_literal: true

require "json"
require "json-schema"

class Release::ReleaseNotesConfigHelper
  JSON_SCHEMA_PATH = "#{__dir__}/schemas/release_notes_config_schema.json"

  # Which sections/fields of the release note config
  # are able to be overridden by configuration options
  ALLOWED_RELEASE_NOTE_CONFIG_OVERRIDES = {
    "changelog" => %w[categories exclude],
  }.freeze

  def initialize(release_config_file)
    @release_config_file = release_config_file
  end

  attr_reader :release_config_file

  # load config from yaml file and turn it into a useable object
  # Returns:
  #   A hash of validated config options than can be used in the release note generation process
  def configuration_hash
    return @configuration_hash if defined?(@configuration_hash)
    config_options = load_config_from_file
    @configuration_hash = parse_config_options(config_options)
  end

  # Loads the repo's release note config
  # uses the current target branch's config file if it exists
  # handles any errors from YAML.safe_load and raises a Releases::Error instead
  def load_config_from_file
    yaml_string = @release_config_file&.data
    yaml_string && YAML.safe_load(yaml_string)
  # errors possible from invalid yaml passed to YAML.safe_load
  rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => e
    raise Releases::Error, "Could not parse #{@release_config_file&.path}: #{e.message}"
  end

  # Parse supplied config options and fill in default config variables.
  # Raise Releases::Error if the provided options are invalid per the config json schema
  #
  # Params:
  #   config_options - a hash of release note options. Keys supported are listed in ALLOWED_RELEASE_NOTE_CONFIG_OVERRIDES.
  #
  # Returns:
  #   A hash containing variable names as keys and their associated value. Default values are found in the json schema.
  def parse_config_options(config_options)
    config_options ||= {}
    configuration_hash = {}

    # insert only the allowed overrides into the configuration
    ALLOWED_RELEASE_NOTE_CONFIG_OVERRIDES.each do |section, overrideable_fields|
      section_override = config_options.try(:dig, section)
      next unless section_override.present?

      if overrideable_fields.any?
        # if specific field overrides are expected, use them
        configuration_hash[section] = {}
        overrideable_fields.each do |field|
          field_override = section_override.try(:dig, field)
          configuration_hash[section][field] = field_override if field_override.present?
        end
      else
        # if there are no specific fields, the entire section is overridden
        configuration_hash[section] = section_override
      end
    end

    # validate and fill in defaults for the configuration
    errors = JSON::Validator.fully_validate(
      JSON_SCHEMA_PATH,
      configuration_hash,
      parse_data: false, # this means we are validating a ruby object, not a json string
      insert_defaults: :true, # this populates the object with the default values from the schema
      errors_as_objects: true
    )

    if errors.any?
      # JSON::Validator errors will by default have the text "in schema <file path to schema>" at the end.
      # This block just removes that from each error message before returning
      errors = errors.pluck(:message).map do |msg|
        if msg&.include?("in schema")
          msg.slice(0..(msg.index("in schema") - 2))
        end
      end.compact

      raise Releases::ConfigurationError, errors
    end

    configuration_hash
  end
end
