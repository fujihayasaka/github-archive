# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class ServerToServerAuthorizer < AuthorizerBase
      delegate :access_grant,
               :current_integration_installation,
               :current_repo,
               :current_repo_loaded?,
               :repo_nwo_from_path,
               :set_forbidden_message, to: :auth_context

      def authorized?(verb, options = nil) # TODO: Remove `options` when all the other programmatic authorizers no longer rely on them
        # Dashboards are user-specific, and are never available to installations.
        if auth_context.dashboard_resource?
          return stepped(
            reason: "dashboard_resource",
            decision: :forbidden,
            disclose_subject_existence: false,
          )
        end

        # on endpoint that allows integrations
        if auth_context.server_to_server_request_allowed?
          integration_authorized = access_grant(verb, auth_context.access_allowed_options).access_allowed?

          if !integration_authorized
            # because the first check fails open, ensure we're not leaking existence of enterprises, teams or spammy users
            if current_integration_installation_can_see_repo? && current_integration_can_be_aware_of_resource?
              stepped(
                reason: "resource_not_accessible_by_integration",
                disclose_subject_existence: true,
                decision: :forbidden
              )

              set_forbidden_message("Resource not accessible by integration")
            else
              stepped(
                reason: "resource_not_accessible_by_integration",
                disclose_subject_existence: false,
                decision: :forbidden
              )

              false
            end
          else
            stepped(
              reason: "resource_accessible_by_integration",
              disclose_subject_existence: true,
              decision: :success
            )
            integration_authorized
          end
        else
          # on endpoint that doesn't allow integrations
          if auth_context.should_set_forbidden_message_if_possible? || current_integration_installation_can_see_repo?
            stepped(
              reason: "resource_not_enabled_for_integrations",
              disclose_subject_existence: true,
              decision: :forbidden
            )

            set_forbidden_message("Resource not accessible by integration")
          else
            stepped(
              reason: "resource_not_enabled_for_integrations",
              disclose_subject_existence: false,
              decision: :forbidden
            )

            false
          end
        end
      end

      # Private: Determines whether the current_integration_installation can know if the current_repo exists
      #
      # NOTE: This _heavily_ relies on the fact that we default to true.
      # The logic needs to be cleaned up to not rely that.
      #
      # Returns a Boolean.
      def current_integration_installation_can_see_repo?
        return true unless current_repo_loaded? || repo_nwo_from_path.present?
        return true unless current_repo.try(:private?)
        return true unless current_integration_installation.present?

        current_integration_installation.repository_ids(repository_ids: [current_repo.id]).include?(current_repo.id)
      end

      def current_integration_can_be_aware_of_resource?
        case auth_context.resource_type
        when :user; !auth_context.resource.spammy?
        when :team; false
        else; true
        end
      end
    end
  end
end
