# typed: true
# frozen_string_literal: true

module User::RemoteAuthenticationDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_many :oauth_applications,
      -> { order("name ASC") },
      dependent: :destroy

    has_many :oauth_accesses,       dependent: :destroy
    has_many :oauth_authorizations, dependent: :destroy
  end

  # Array of OauthAccess scopes.  See OAuthAccess#access_level
  attr_accessor :oauth_access

  # Signed Auth Token the user is currently authenticating with.
  attr_accessor :sat_context

  # Integer ID of the OAuth Application that this user is currently accessing.
  attr_accessor :oauth_application_id

  # Required by Egress. Should supersede :oauth_access eventually
  attr_accessor :scopes

  # IntegrationInstallation, if the user's request is within the context
  # of a specific installation.
  attr_accessor :access_context

  attr_accessor :programmatic_access

  def can_authenticate_via_oauth?
    true
  end

  def can_authenticate_via_basic_auth?
    true
  end

  def can_authenticate_via_username_password_basic_auth?
    true
  end

  def using_oauth?
    !scopes.nil?
  end

  def using_basic_auth?
    return false unless can_authenticate_via_username_password_basic_auth?

    !oauth_access && !using_oauth? && !programmatic_access
  end

  def using_personal_access_token?
    oauth_access.present? && oauth_access.personal_access_token?
  end

  def using_auth_via_integration?
    oauth_access.present? && oauth_access.integration_application_type?
  end

  def using_auth_via_oauth_application?
    oauth_access.present? && oauth_access.oauth_application_type?
  end

  def using_auth_via_user_programmatic_access?
    programmatic_access.present? && ProgrammaticAccess.user_type?(programmatic_access)
  end

  def using_auth_via_granular_actor?
    using_auth_via_integration? || using_auth_via_user_programmatic_access?
  end

  def using_app_with_copilot_token_capability?
    (using_auth_via_integration? || using_auth_via_oauth_application?) \
      && Apps::Privileged.capable?(:generate_copilot_cdn_token, app: oauth_access.application)
  end

  def using_auth_via_signed_auth_token?
    sat_context.present? && sat_context.valid?
  end

  # Checks to see if the user has access to any of the given scopes.  The
  # user scopes are set by User.with_oauth_token.  If the user was loaded
  # by some other means, it is assumed they did not login with OAuth, and
  # therefore have access to all scopes.
  #
  # scopes - Array of Symbols that represent OAuth scopes.  See
  #          OauthAccess.access_level! to see how the String scopes that apps
  #          give us are converted to the Symbol scopes the app uses.
  #
  # Returns true if the user has access to one or more of the given scopes, or
  # false.
  def oauth_access?(*scopes)
    @oauth_access.nil? || oauth_access.scopes?(*scopes)
  end

  # Public: Get or generate a secret to be used for signed auth tokens.
  #
  # Returns a 40 character string of random hex.
  def signed_auth_token_secret
    return token_secret unless token_secret.blank?
    ActiveRecord::Base.connected_to(role: :writing) do
      regenerate_token_secret
      save
    end
    token_secret
  end

  def regenerate_token_secret
    self[:token_secret] = SecureRandom.hex(20)
  end

  def signed_auth_token(options = {})
    options[:user] = self
    GitHub::Authentication::SignedAuthToken.generate(**options)
  end

  # Public: User is authenticating with OAuth via an OAuth application, not via
  # a personal access token.
  #
  # Returns true if they are, false otherwise
  def using_oauth_application?
    using_oauth? && !oauth_access&.personal_access_token?
  end

  # Public: The OauthApplication that is currently acting on behalf of the user.
  #
  # Returns an OauthApplication, or nil if the user is not authenticating via an
  #   OAuth application.
  def oauth_application
    return nil unless using_oauth_application?

    oauth_access.application
  end

  # Public: Determine whether organization application policies are enabled and
  # the user is authenticating with OAuth via an OAuth application.
  #
  # Returns a Boolean.
  def governed_by_oauth_application_policy?
    GitHub.oauth_application_policies_enabled? && using_oauth_application?
  end

  def restricts_oauth_applications?
    false
  end

  def programmatic_ability_delegate_for_repository(repository)
    T.bind(self, User)

    if self.try(:installation)
      # dynamically written method does not always exist on users
      T.unsafe(self).installation
    elsif app = oauth_access&.integration
      IntegrationInstallation.with_repository(repository).find_by(integration: app) || GlobalIntegrationInstallation.for_repository(app, repository)
    elsif self.try(:programmatic_access)
      self.programmatic_access.grant_for_repository(repository)
    end
  end

  class_methods do
    # Public: Verify a SignedAuthToken string.
    #
    # :token - The string token to verify.
    # :scope - The scope that the token should match.
    #
    # Returns SignedAuthToken instance.
    def verify_signed_auth_token(token:, scope:)
      GitHub::Authentication::SignedAuthToken.verify(token: token, scope: scope).tap do |token|
        # If the token was generated for a Bot, we need to fill in what IntegrationInstallation
        # the Bot is trying to use for its permissions.
        if token.user&.is_a?(Bot)
          installation = find_installation(token.installation_type, token.installation_id)

          if installation.nil? && ActiveRecord::Base.connected_to?(role: :reading) && FeatureFlag.vexi.enabled?(:signed_auth_token_installation_fallback_to_primary, default: false)
            installation = ActiveRecord::Base.connected_to(role: :writing) do
              find_installation(token.installation_type, token.installation_id)
            end

            GitHub.dogstats.increment("signed_auth_token.installation.fallback_to_primary", tags: ["installation_type:#{token.installation_type}", "found_on_primary:#{!installation.nil?}"])
          end

          token.user = installation.bot if installation&.bot
        end
      end
    end

    # Public: Authenticate a SignedAuthToken string.
    #
    # :token - The string token to verify.
    # :scope - The scope that the token should match.
    #
    # Returns the authenticated user or nil.
    def authenticate_with_signed_auth_token(token:, scope:)
      verify_signed_auth_token(token: token, scope: scope).user
    end

    private

    def find_installation(installation_type, installation_id)
      if installation_type == "ScopedIntegrationInstallation"
        ScopedIntegrationInstallation.includes(:integration).find_by(id: installation_id)
      elsif installation_type == "SiteScopedIntegrationInstallation"
        SiteScopedIntegrationInstallation.includes(:integration).find_by(id: installation_id)
      else
        IntegrationInstallation.includes(:integration).find_by(id: installation_id)
      end
    end
  end
end
