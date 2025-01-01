# typed: true
# frozen_string_literal: true
class OpenapiBreakingChangeGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  class_option :description_path,
    type: :string,
    required: true,
    desc: "Path to the existing OpenAPI component or operation description where you want to make breaking changes"

  class_option :changeset_path,
    type: :string,
    required: true,
    desc: "Path to the existing OpenAPI changeset describing the breaking change"

  def create
    ensure_paths_exists

    changeset = OpenApi::Description::Changeset.from(YAML.load_file(options[:changeset_path]))
    description = YAML.load_file(options[:description_path])

    existing_breaking_changes = description["x-github-breaking-changes"] || []

    check_existing_breaking_changes(existing_breaking_changes, changeset.name)
    add_new_breaking_change(existing_breaking_changes, changeset.name, description)
  end

  private

  def ensure_paths_exists
    errors = []
    errors << "Description path does not exist: #{options[:description_path]}" unless File.exist?(options[:description_path])
    errors << "Changeset path does not exist: #{options[:changeset_path]}" unless File.exist?(options[:changeset_path])
    raise ArgumentError, errors.join("\n") unless errors.empty?
  end

  def check_existing_breaking_changes(existing_breaking_changes, changeset_name)
    if existing_breaking_changes.any? { |bc| bc["changeset"] == changeset_name }
      raise ArgumentError, "Description already has breaking changes for the changeset '#{changeset_name}'"
    end
  end

  def add_new_breaking_change(existing_breaking_changes, changeset_name, description)
    new_breaking_change = {
      "changeset" => changeset_name,
      "patch" => {},
    }

    description["x-github-breaking-changes"] = (existing_breaking_changes << new_breaking_change)
    File.write(options[:description_path], YAML.dump(description))
  end
end
