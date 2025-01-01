# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateLabel < Platform::Mutations::Base
      description "Creates a new label."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :color, String, "A 6 character hex code, without the leading #, identifying the color of the label.", required: true
      argument :name, String, "The name of the label.", required: true
      argument :description, String, "A brief description of the label, such as its purpose.", required: false

      error_fields
      field :label, Objects::Label, "The new label.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :create_repo_label, current_org: org, repo: repository, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(repository:, execution_errors:, **inputs)
        context[:permission].authorize_content(:label, :create, repository: repository)

        label = repository.labels.build
        label.color = inputs[:color]
        label.name = inputs[:name]
        label.description = inputs[:description]

        if label.save
          {
            label: label,
            errors: [],
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(label, execution_errors)

          {
            label: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(label),
          }
        end
      end
    end
  end
end
