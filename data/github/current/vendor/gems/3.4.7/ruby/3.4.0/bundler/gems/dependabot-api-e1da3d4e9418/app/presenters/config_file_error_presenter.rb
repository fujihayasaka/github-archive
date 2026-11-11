# frozen_string_literal: true

class ConfigFileErrorPresenter
  def initialize(error_hash:, config_file_path:)
    @error_hash = error_hash
    @config_file_path = config_file_path
  end

  def issue_type
    error_hash.fetch("error-type")
  end

  def issue_detail
    error_message = error_hash["error-detail"]&.
                    fetch("message", nil)

    case issue_type
    when "unparseable_config_file" then error_message
    when "invalid_config_file" then error_message
    else raise "Unexpected error type: #{issue_type}"
    end
  end

  def issue_title
    case issue_type
    when "unparseable_config_file" then unparseable_config_file_title
    when "invalid_config_file" then invalid_config_file_title
    else raise "Unexpected error type: #{issue_type}"
    end
  end

  def issue_body
    case issue_type
    when "unparseable_config_file" then unparseable_config_file_body
    when "invalid_config_file" then invalid_config_file_body
    else raise "Unexpected error type: #{issue_type}"
    end
  end

  private

  attr_reader :error_hash, :config_file_path

  def unparseable_config_file_title
    "Dependabot couldn't parse the config file at #{config_file_path}"
  end

  def unparseable_config_file_body
    "Dependabot couldn't parse the config file at `#{config_file_path}`. "\
    "The error raised was:"\
    "\n\n```\n#{issue_detail}\n```\n\n" \
    "Please ensure the config file is a valid YAML file. An online YAML "\
    "linter is available [here](https://jsonformatter.org/yaml-validator)."
  end

  def invalid_config_file_title
    "Your #{config_file_path} contained invalid details"
  end

  def invalid_config_file_body
    "Dependabot encountered the following error when parsing your "\
    "`#{config_file_path}`:\n\n"\
    "```\n#{issue_detail}\n```\n\n" \
    "Please update the config file to conform with Dependabot's specification."
  end
end
