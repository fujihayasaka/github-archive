# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Updates config/config_file_json_schema.json with new ecosystem definitions
class EcosystemOnboarding
  class JsonSchemaUpdater < BaseUpdater
    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      changes = []
      manual_steps = []

      schema_file = root_path.join("config/config_file_json_schema.json")
      return { changes: changes, manual_steps: manual_steps } unless File.exist?(schema_file)

      change_desc = "Add #{ecosystem_name} to config JSON schema"
      return { changes: changes, manual_steps: manual_steps } unless should_proceed?(schema_file, change_desc)

      schema = JSON.parse(File.read(schema_file))

      # Add to package-ecosystem enum
      changes.concat(add_to_ecosystem_enum(schema))

      # Add ecosystem definition
      changes.concat(add_ecosystem_definition(schema))

      # Write back to file with pretty formatting
      File.write(schema_file, JSON.pretty_generate(schema))
      Rails.logger.debug "✓ Updated config JSON schema"

      { changes: changes, manual_steps: manual_steps }
    rescue JSON::ParserError => e
      Rails.logger.debug { "✗ Error parsing JSON schema: #{e.message}" }
      { changes: [], manual_steps: [] }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating config JSON schema: #{e.message}" }
      { changes: [], manual_steps: [] }
    end

    private

    sig { params(schema: T::Hash[String, T.untyped]).returns(T::Array[String]) }
    def add_to_ecosystem_enum(schema)
      changes = []

      if schema.dig("definitions", "package-ecosystem",
                    "enum") && schema["definitions"]["package-ecosystem"]["enum"].exclude?(ecosystem_name)
        schema["definitions"]["package-ecosystem"]["enum"] << ecosystem_name
        changes << "Added #{ecosystem_name} to package-ecosystem enum"
      end

      changes
    end

    sig { params(schema: T::Hash[String, T.untyped]).returns(T::Array[String]) }
    def add_ecosystem_definition(schema)
      changes = []

      if schema["definitions"][ecosystem_name]
        Rails.logger.debug { "⚠ #{ecosystem_name} definition already exists in schema" }
      else
        schema["definitions"][ecosystem_name] = build_ecosystem_schema
        changes << "Added #{ecosystem_name} schema definition (TODO: customize properties as needed)"
      end

      changes
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build_ecosystem_schema # rubocop:disable Metrics/MethodLength
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "package-ecosystem" => { "enum" => [ecosystem_name] },
          "directory" => { "$ref" => "#/definitions/directory" },
          "directories" => { "$ref" => "#/definitions/directories" },
          "target-branch" => { "$ref" => "#/definitions/target-branch" },
          "commit-message" => { "$ref" => "#/definitions/commit-message" },
          "schedule" => { "$ref" => "#/definitions/with_batch_schedules" },
          "reviewers" => { "$ref" => "#/definitions/reviewers" },
          "assignees" => { "$ref" => "#/definitions/assignees" },
          "labels" => { "$ref" => "#/definitions/labels" },
          "milestone" => { "$ref" => "#/definitions/milestone" },
          "allow" => { "$ref" => "#/definitions/allow" },
          "ignore" => { "$ref" => "#/definitions/ignore" },
          "open-pull-requests-limit" => { "$ref" => "#/definitions/open-pull-requests-limit" },
          "rebase-strategy" => { "$ref" => "#/definitions/rebase-strategy" },
          "insecure-external-code-execution" => { "$ref" => "#/definitions/insecure-external-code-execution" },
          "registries" => { "$ref" => "#/definitions/registries" },
          "groups" => { "$ref" => "#/definitions/groups" },
          "exclude-paths" => { "$ref" => "#/definitions/exclude-paths" },
        },
      }
    end
  end
end
