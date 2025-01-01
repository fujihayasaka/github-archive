# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateCheckSuitePreferences < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Modifies the settings of an existing check suite"

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :auto_trigger_preferences, [Inputs::CheckSuiteAutoTriggerPreference], "The check suite preferences to modify.", required: true

      field :repository, Objects::Repository, "The updated repository.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:set_check_suite_preferences, resource: repo, current_org: org, current_repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(repo:, **inputs)

        inputs[:auto_trigger_preferences].each do |preference|
          app = Platform::Helpers::NodeIdentification.typed_object_from_id([Objects::App], preference[:app_id], context)
          id = app.id
          unless allowed_to_modify_app?(app_id: id) # effectively, a 403
            raise Platform::Errors::Unprocessable.new("Invalid app_id `#{preference[:app_id]}` - check suite can only be modified by the GitHub App that created it.")
          end
          app = Integration.find_by(id: id)
          repo.set_auto_trigger_checks(actor: context[:viewer], app: app, value: preference[:setting].to_s)
        end

        { repository: repo }
      end
    end
  end
end
