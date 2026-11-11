# typed: true
# frozen_string_literal: true

require "open_api"

# Named without a capital "A" to support "openapi_changeset" on the command line.
class OpenapiChangesetGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  def create_changeset
    validate_file_name!

    template "changeset.yaml.erb", "app/api/description/changesets/#{numbered_file_name}.yaml"
  end

  private

  # A migration file name can only contain underscores (_), lowercase characters,
  # and numbers 0-9. Any other file name will raise an IllegalApiChangesetNameError.
  def validate_file_name!
    unless OpenApi::Description::Changeset.valid_name?(file_name)
      raise OpenApi::Description::InvalidChangesetNameError.new(file_name)
    end
  end

  def numbered_file_name
    existing_changeset = OpenApi::Description::Changeset.find_path(file_name)
    if existing_changeset
      existing_changeset.basename(".yaml")
    else
      dir, base = File.split(file_name)
      File.join(dir, [changeset_timestamp, base].join("_"))
    end
  end

  # Determines the timestamp of the next changeset.
  def changeset_timestamp
    Time.now.utc.strftime("%Y%m%d%H%M%S")
  end

  def release_date_default
    1.month.from_now.utc.strftime("%Y-%m-%d")
  end
end
