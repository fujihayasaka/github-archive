# typed: true
# frozen_string_literal: true

module Codespaces
  # Actions for the VSCode LWE (AKA serverless and github.dev)
  class LightweightWebEditorController < ApplicationController
    before_action :login_required

    layout "layouts/minimal"
    stylesheet_bundle "lightweight-web-editor"
    javascript_bundle "lightweight-web-editor"

    preload_features [:codespaces_developer]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      only: [:auth]

    # This endpoint will be redirected to by VSCS when users visit a
    # github.dev page with no editor session.
    # It renders a loading page that will form post an oauth token and other
    # metadata to the auth server to set up an editor session.
    def auth # rubocop:todo GitHub/UseRestfulActions
      assert_preconditions
      return if performed?

      add_to_csp
      render "codespaces/lightweight_web_editor/auth", locals: {
        auth_server_uri: auth_server_uri.to_s,
        partner_info: partner_info
      }
    end

    # This auth endpoint issues a broadly scoped OAuth token for the
    # authenticated user, so it has no RFCA *per se*.  However, the
    # required redirect param is a GitHub URL path that the user attempted to
    # access.  This path may refer to an org-owned repo.  For example,
    #
    #   ?redirect=github/github/blob/master/Gemfile
    #
    # If we can detect the repo the user is attempting to access in github.dev,
    # we should treat that as the CAP resource so that external identity
    # session policies can be enforced before minting a token that otherwise
    # might not work with the requested repo anyway.
    # The use of :no_resource_for_conditional_access below if we fail to detect
    # the repo from the redirect param cannot cause a conditional access bypass
    # because this endpoint only issues tokens and all actual access to the
    # underlying resources will be mediated by the REST and GraphQL API calls
    # made from github.dev.
    # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    def resource_for_conditional_access # rubocop:todo GitHub/UseRestfulActions
      return @resource_for_conditional_access if defined?(@resource_for_conditional_access)
      parts = params[:redirect].to_s.split("/")
      parts.shift if parts.first == "" # strip leading slash
      if parts.size < 2
        # it's ok if we can't recognize the repo in the redirect param or one isn't there
        return @resource_for_conditional_access = :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
      end
      @resource_for_conditional_access = \
        Repository.with_name_with_owner(parts[0], parts[1]) || :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    end
    # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

    private def target_for_conditional_access
      return :no_target_for_conditional_access unless resource_for_conditional_access.is_a?(Repository) # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      resource_for_conditional_access.owner
    end

    private

    ALLOWED_PARAMS = %w[host redirect requestId].freeze

    def assert_preconditions
      return head :unauthorized if request.xhr?
      return render_404 unless GitHub.codespaces_serverless_editor_enabled?

      # There are three supported params.  This one is required.
      # TODO: make requestId required once github.dev is updated to include it.
      return head :bad_request unless request.params[:redirect]

      # We copy the query string verbatim into auth_server_uri, so
      # make sure there's nothing we don't expect there.
      return head :bad_request unless request.query_parameters.keys.all? { |key| key.in?(ALLOWED_PARAMS) }
      unless auth_server_host.in?(allowed_redirect_hosts)
        head :bad_request
      end
    end

    # Ensure we are posting credentials to a safe host.
    # Codespaces developers can use some additional ones.
    def allowed_redirect_hosts
      if user_feature_enabled?(:codespaces_developer)
        (
          GitHub.codespaces_serverless_allowed_auth_redirect_hosts |
          GitHub.codespaces_serverless_developer_restricted_auth_redirect_hosts
        )
      else
        GitHub.codespaces_serverless_allowed_auth_redirect_hosts
      end
    end

    # The auth endpoint makes a client side form POST to a host outside our
    # standard CSP, which needs to be explicitly allowed for that action.
    # For performance we also execute the form post as an inline script,
    # the hash of which needs to be added to the CSP for this page as well.
    def add_to_csp
      form_uri = URI::Generic.build(
        scheme: auth_server_uri.scheme,
        host: auth_server_uri.host,
        port: auth_server_uri.port,
      ).to_s

      SecureHeaders.append_content_security_policy_directives(
        request,
        form_action: [form_uri],
        script_src: ["'sha256-HlCcEJBPa0ZrWMRh16WwNdfZOR/jwpCONoNBPlzHI5U='"],
        preserve_schemes: user_feature_enabled?(:codespaces_developer), # We need to preserve schemes to support http for the devstamp
      )
    end

    # The endpoint we will post credentials and metadata to which will redirect
    # the browser to the editor.
    def auth_server_uri # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @auth_server_uri if defined?(@auth_server_uri)

      base = URI.parse("https://#{auth_server_host}")
      @auth_server_uri = URI::Generic.build(
        scheme: base.host&.end_with?(".localhost") ? "http" : base.scheme,
        host: base.host,
        port: base.port,
        requestId: auth_server_request_id,
        # We have to pass the `redirect` query param we received back to the
        # auth server, also as a query param.
        query: request.query_string
      )
    end

    # The callback request may include a `host` param representing the server
    # to post credentials to.  This is to support multiple VSCS environments
    # and local development.  This is safe because the host is validated to be
    # a member of a predefined allowlist in the assert_preconditions method.
    def auth_server_host # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @auth_server_host ||= \
        params[:host] || GitHub.codespaces_serverless_default_auth_redirect_host
    end

    # The callback request could include a `requestId` param representing the
    # request ID of the original request.
    # This is to ensure that the we are serving the response to the client that
    # originated the call.
    # With this we are adding an extra security layer to the auth request as well
    # as being able to prevent better authentication loops between dotcom and github.dev.
    def auth_server_request_id # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @auth_server_request_id if defined?(@auth_server_request_id)
      @auth_server_request_id = params[:requestId]
    end

    # Generate the JSON payload needed to authenticate and configure the editor.
    def partner_info
      Codespaces::LightweightWebEditor.partner_info(
        user: current_user,
        token: mint_oauth_token,
        host: GitHub.host_name
      )
    end

    # Mint a new OAuth token for the user against the LWE app.
    def mint_oauth_token
      Codespaces::Tokens.mint_web_editor_oauth_token(
        user: current_user,
        session: user_session
      )
    end
  end
end
