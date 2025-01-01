# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MigrationImportMapping < Platform::Inputs::Base
      description "Specifies a migration import mapping."
      feature_flag :gh_migrator_import_to_dotcom

      argument :model_name, String, "The model in a migration import mapping.", required: true
      argument :source_url, String, "The resource URL to migrate data from in a migration import mapping.", required: true
      argument :target_url, String, "The resource URL to migrate data to in a migration import mapping.", required: true
      argument :action, Enums::ImportMapAction, "The mapping action that will take place during a migration import.", required: true
    end
  end
end
