# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateLabelByName < Platform::Mutations::Base
      description "Updates an existing label by name."

      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository the label belongs to.", required: true, loads: Objects::Repository
      argument :subject_name, String, "The name of the label to be updated.", required: true
      argument :color, String, "A 6 character hex code, without the leading #, identifying the updated color of the label.", required: false
      argument :name, String, "The updated name of the label.", required: false

      field :label, Objects::Label, "The updated label.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed? :update_repo_label, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(repository:, **inputs)

        context[:permission].authorize_content(:label, :update, repository: repository)

        label = repository.labels.find_by_name(inputs[:subject_name])
        raise Errors::NotFound.new("Could not find label '#{inputs[:subject_name]}' for repository '#{repository.owner.name}/#{repository.name}'.") unless label

        check_database_resource_update_rate_limit!(resource: label, current_user: context[:viewer])

        label.color = inputs[:color] if inputs.key?(:color)
        label.name = inputs[:name] if inputs.key?(:name)

        if label.save # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          { label: label }
        else
          raise Errors::Unprocessable.new(label.errors.full_messages.join(", "))
        end
      end
    end
  end
end
