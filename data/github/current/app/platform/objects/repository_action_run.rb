# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryActionRun < Platform::Objects::Base
      visibility :internal
      description "A RepositoryAction run."
      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_suite.then do |check_suite|
          permission.typed_can_see?("CheckSuite", check_suite)
        end
      end

      field :started_at, Scalars::DateTime, description: "Identifies the date and time when the action run was started.", null: true

      field :completed_at, Scalars::DateTime, description: "Identifies the date and time when the action run was completed.", null: true

      field :duration, Integer, description: "The time it took to run the action (in seconds).", null: false, visibility: :internal

      def duration
        return 0 unless @object.completed_at

        (@object.completed_at - (@object.started_at || @object.completed_at)).floor
      end

      field :status, Enums::CheckStatusState, description: "The current status of the action run.", null: false

      field :conclusion, Enums::CheckConclusionState, description: "The conclusion of the action run.", null: true

      field :title, String, description: "A string representing the action run", null: true

      field :summary, String, description: "A string representing the action run's summary", null: true

      field :text, String, description: "A string representing the action run's text", null: true

      field :details_url, Scalars::URI, description: "The URL from which to find full details of the action run on the integrator's site.", null: true

      def details_url
        @object.async_check_suite.then do |check_suite|
          check_suite.async_github_app.then do |_app|
            @object.details_url
          end
        end
      end

      field :action, Objects::RepositoryAction, null: true, description: "The action that was executed.", visibility: :internal

      def action
        # This isn't an action run if the external_id is empty.
        return if @object.external_id.to_s.empty?
        @object.async_check_suite.then do |check_suite|
          ::RepositoryAction.from_external_id(external_id: @object.external_id,
            repository_id: check_suite.repository_id,
            ghost_allowed: true, default_title: @object.name)
        end
      end

      field :repository, Objects::Repository, "The repository associated with this action run.", method: :async_repository, null: false

      field :name, String, description: "The name of the check for this action run.", null: false

      field :permalink, Scalars::URI, description: "The permalink to the action run summary.", null: false

      def permalink
        @object.async_repository.then do
          Addressable::URI.parse(@object.permalink(include_host: true))
        end
      end
    end
  end
end
