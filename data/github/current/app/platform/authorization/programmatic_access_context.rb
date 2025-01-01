# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    # TODO: https://github.com/github/ecosystem-apps/issues/1617
    class ProgrammaticAccessContext
      attr_reader :request_authn_context, :repo_nwo_from_path, :current_resource_owner

      # TODO: Directly accessing access_allowed_options is a last resort and
      # should be avoided at all costs. This accessor should eventually be
      # removed.
      attr_reader :access_allowed_options

      delegate :access_grant,
               :current_user,
               :current_integration,
               :current_integration_installation,
               :current_parent_integration_installation,
               :current_repo_loaded?,
               :current_repo,
               :current_user_programmatic_access,
               :graphql_request?,
               :global_integration_user_request?,
               :integration_bot_request?,
               :integration_user_request?,
               :set_forbidden_message,
               :user_programmatic_access_request?,
               :user_request?,
               :write_request?,
               to: :request_authn_context

      # Public: instantiate a new ProgrammaticAccessContext for use during API
      # authorization.
      #
      # request_authn_context   - Object: Provides information about the authenticated
      #                           actor(s). Typically a class that `include`s
      #                           Platform::Authorization.
      # repo_nwo_from_path      - String: The repository name with owner: E.g.
      #                           "github/github" associated with the current
      #                           API context.
      # current_resource_owner  - Object: The owner of the current API resource
      #                           (E.g. the "subject" of an authorization policy).
      # access_allowed_options  - Hash: The `options` argument passed to
      #                           authorization methods like `control_access`
      #                           and `access_allowed?`. TODO: Encapsulate
      #                           these options and provide validation.
      #
      # Returns a Platform::Authorization::ProgrammaticAccessContext object.
      def initialize(request_authn_context:, repo_nwo_from_path:, current_resource_owner:, access_allowed_options:)
        @request_authn_context = request_authn_context
        @repo_nwo_from_path = repo_nwo_from_path
        @current_resource_owner = current_resource_owner
        @access_allowed_options = access_allowed_options
      end

      def user_via_granular_actor_request_allowed?
        # TODO: rename this flag globally
        # https://github.com/github/ecosystem-apps/issues/1634
        @access_allowed_options.fetch(:allow_user_via_granular_actor, false)
      end

      def server_to_server_request_allowed?
        @access_allowed_options.fetch(:allow_integrations, false)
      end

      def resource_type
        return :business if resource.is_a?(Business)
        return :dashboard if Platform::ResourceUtils.is_dashboard_type?(resource)
        return :team if team_resource?
        return :user if resource.is_a?(User)
        return :none if resource.nil?
        :unknown
      end

      def resource
        @access_allowed_options[:resource]
      end

      def team_resource?
        @access_allowed_options[:team].present? || resource.is_a?(Team)
      end

      def business_resource?
        resource_type == :business
      end

      def dashboard_resource?
        resource_type == :dashboard
      end

      def should_set_forbidden_message_if_possible?
        !!@access_allowed_options.fetch(:forbid, false)
      end

      # Primarily for database filtering, we don't want to simply raise an error if a GitHub App
      # doesn't have access to a resource. In those cases, we'll just return with `false` and
      # let the resolver handle the next move. Only applicable to GraphQL
      # requests.
      def raise_on_error?
        !!@access_allowed_options.fetch(:raise_on_error, true)
      end
    end
  end
end
