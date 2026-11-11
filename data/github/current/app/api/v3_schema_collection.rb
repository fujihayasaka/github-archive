# typed: true
# frozen_string_literal: true

module Api
  # The ApiSchema::Collection describing GitHub API v3.
  #
  # Defining the collection as a constant allows us to load the schemas at boot
  # Used in App::Api as well models like IntegrationManifest
  V3SchemaCollection = ApiSchema::Collection.load(GitHub.api_subschema_dir)
end
