# typed: true
# frozen_string_literal: true

# Decides if and where to redirect installers after perfoming an installation
# related action on an App. E.g. should we redirect the user to a setup URL
# after initial installation?
#
# Builds a redirect URL containing query parameters relevant to the integrator.
# E.g. redirectUrl and installation_id.
class Integration
  class InstallerRedirect

    attr_reader   :integration, :installation, :return_to_url, :referring_sha, :setup_state_cookie
    attr_accessor :oauth_access

    # Public: instantiate a new InstallerRedirect object.
    #
    # integration     - The GitHub App on which an action has been performed.
    # installation    - The Installation instance of the GitHub App (Optional).
    # action          - A Symbol represeting the action taken on the app. One of
    #                   [:install, :update]
    # return_to_url   - A String representing the URL that the integrator should
    #                   redirect the installer to (Optional).
    # referring_sha   - A String representing the Git OID that instigated
    #                   the integration installation (Optional).
    # oauth_access    - An Oauth::Access instance from which to take the code
    #                   to use as a parameter in the redirect URL.
    # setup_state_cookie - A SetupStateCookie used to pass state overrides (Optional).
    def initialize(integration:, installation: nil, action:, return_to_url: nil, referring_sha: nil, oauth_access: nil, setup_state_cookie: nil)
      @action = action
      @integration = integration
      @installation = installation
      @return_to_url = return_to_url
      @referring_sha = referring_sha
      @oauth_access = oauth_access
      @setup_state_cookie = setup_state_cookie
    end

    # Public: Should the installer be redirected after this action?
    #
    # Returns a Boolean.
    def should_redirect?
      return @should_redirect if defined?(@should_redirect)
      @should_redirect =
        case action
        when :install, :request
          integration.additional_setup_required?
        when :install_and_oauth, :request_and_oauth
          true
        when :update, :update_and_oauth
          integration.setup_on_update?
        else
          false
        end
    end

    # Public: The URL an installer should be redirected to given the action.
    #
    # Returns a String.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def url
      @url ||=
        case action
        when :install_and_oauth, :update_and_oauth, :request_and_oauth
          build_uri(integration.callback_url).to_s
        when :install, :update, :request
          build_uri(integration.setup_url).to_s
        end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    private

    # Private: the installation action that is being performed on the App.
    # Distinguishes between the following actions:
    #
    # - :install
    # - :install_and_oauth
    # - :update
    #
    # Returns a Symbol.
    def action
      if integration.can_request_oauth_on_install?
        "#{@action}_and_oauth".to_sym
      else
        @action
      end
    end

    def build_uri(base_url)
      @uri ||=
        begin
          uri = Addressable::URI.parse(base_url)
          uri.query_values = uri.query_values.to_h.merge(query_params)
          uri
        end
    end

    def query_params
      @query_params ||= {}.tap do |opts|
        opts[:setup_action] = setup_action_for_param if valid_setup_action_for_param?
        opts[:installation_id] = installation.id if installation.present?
        if return_to_url.present?
          # TODO: deprecate redirectURL in favor of redirect_url:
          # https://github.com/github/ecosystem-apps/issues/666
          opts[:redirectUrl] = return_to_url
          opts[:redirect_url] = return_to_url
        end

        if setup_state_cookie.present?
          state_param = setup_state_cookie.state_param(
            integration_id: integration.global_relay_id,
            target_id: installation&.target_id,
          )
          opts[:state] = state_param if state_param
        end

        opts[:sha] = referring_sha if referring_sha
        opts[:code] = oauth_access.code if oauth_access
        opts[:github_host] = GitHub.host_name_with_tenant if GitHub.multi_tenant_enterprise?
      end
    end

    def valid_setup_action_for_param?
      setup_action_for_param.present?
    end

    def setup_action_for_param
      return @setup_action_for_param if defined?(@setup_action_for_param)
      @setup_action_for_param ||=
        case action
        when :install, :install_and_oauth
          :install
        when :update, :update_and_oauth
          :update
        when :request, :request_and_oauth
          :request
        end
    end
  end
end
