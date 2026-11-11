# typed: strict
# frozen_string_literal: true

module Platform
  module Mutations
    class DismissContentWarning < Platform::Mutations::Base
      description "Dismisses a content warning."

      # We do not want this to be truly public but we also need the mobile app to call it.
      # The issue, if we made this fully public, is we risk a user never actually seeing the
      # content warning via the web or mobile app if they dismissed via the API.
      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes %w[public_repo]

      read_arguments_from_replicas!

      argument :repository_id,
        ID,
        "The Repository ID to dismiss the content warning for.",
        required: true,
        loads: Objects::Repository

      field :repository, Objects::Repository, "The repository for which the content warning was dismissed.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(
          permission: Authorization::Permission,
          repository: ::Repository,
          inputs: T.untyped
        ).returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_api_can_modify?(permission, repository:, **inputs)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(
            :v4_get_repo,
            resource: repository,
            repo: repository,
            current_org: org,
            allow_integrations: false,
            allow_user_via_granular_actor: true
          )
        end
      end

      sig do
        params(repository: ::Repository).returns(Promise[T::Hash[Symbol, T.untyped]])
      end
      def resolve(repository:)
        user = context[:viewer]
        applicator = TrustSafety::ContentWarningApplicator.new(repository, user)

        applicator.async_content_warning.then do |content_warning|
          if content_warning && content_warning[:type] == "banner"
            applicator.dismiss_content_warning_banner!
          elsif content_warning && content_warning[:type] == "interstitial"
            applicator.interstitial_content_warning_opt_in!
          end

          {
            repository: Repositories.domain.reload(repository),
          }
        end
      end
    end
  end
end
