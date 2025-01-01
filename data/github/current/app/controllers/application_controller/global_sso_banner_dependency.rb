# typed: true
# frozen_string_literal: true

# Helper methods for the global SSO banner

module ApplicationController::GlobalSsoBannerDependency
  include GitHub::Memoizer

  extend ActiveSupport::Concern
  extend T::Helpers

  DISMISSED_SSO_ORGS_COOKIE_NAME = "dismissed_sso_orgs"

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, AbstractController::Helpers::ClassMethods)

    helper_method :global_sso_orgs_payload
    helper_method :show_global_sso_banner?
    helper_method :global_sso_banner_enabled_for_current_page?
    helper_method :global_sso_app_payload
  end

  class_methods do
    sig { params(actions: T::Array[Symbol]).void }
    def check_for_sso(actions = [])
      T.unsafe(self).before_action(:initialize_global_sso_prompt, only: actions)
    end
  end

  private

  # Initializes the global SSO prompt variables and display the banner in the app layout.
  sig { params(skip_banner_rendering: T::Boolean).void }
  def initialize_global_sso_prompt(skip_banner_rendering: false)
    return unless logged_in?
    return if global_sso_orgs_initialized?

    @global_sso_orgs = find_global_sso_orgs
    @skip_global_sso_banner_rendering = skip_banner_rendering
  end

  # Initializes the global SSO prompt variables without rendering the SSO banner in the app layout.
  # This method is useful when you need to set up SSO-related state to pass to React
  sig { void }
  def initialize_global_sso_prompt_for_react
    initialize_global_sso_prompt(skip_banner_rendering: true)
  end

  sig { returns(T::Array[Organization]) }
  def find_global_sso_orgs
    unauthorized_accounts = cap_filter.unauthorized(current_user&.resources_for_cap_filter).by_policy
    unauthorized_accounts[:saml] || []
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def global_sso_orgs_payload
    return [] unless logged_in?
    return [] unless global_sso_orgs_initialized? && @global_sso_orgs.any?

    @global_sso_orgs.map do |org|
      {
        id: org.id.to_s,
        login: org.display_login,
        name: org.name,
        avatar_url: helpers.avatar_url_for(org),
      }
    end
  end

  sig { returns(T::Boolean) }
  def show_global_sso_banner?
    return false unless global_sso_banner_enabled_for_current_page?
    return false if @skip_global_sso_banner_rendering

    # Check if the current org IDs match the dismissed ones in the cookie
    !current_sso_orgs_match_dismissed_cookie?
  end

  sig { returns(T::Boolean) }
  def global_sso_banner_enabled_for_current_page?
    return false unless logged_in?

    global_sso_orgs_payload.any?
  end

  # Prevent showing the global SSO banner if the user has already dismissed the exact same set of organizations
  sig { returns(T::Boolean) }
  def current_sso_orgs_match_dismissed_cookie?
    dismissed_cookie = cookies[DISMISSED_SSO_ORGS_COOKIE_NAME]

    return false if dismissed_cookie.blank?

    begin
      dismissed_org_ids = JSON.parse(dismissed_cookie)
      return false unless dismissed_org_ids.is_a?(Array)

      current_org_ids = global_sso_orgs_payload.map { |org| org[:id] }.sort

      # have all of the current_org_ids already been dismissed?
      (current_org_ids - dismissed_org_ids).empty?
    rescue JSON::ParserError
      # Delete malformed cookie
      cookies.delete(DISMISSED_SSO_ORGS_COOKIE_NAME, domain: cookie_domain)
      false
    end
  end

  sig { returns(T::Boolean) }
  def global_sso_orgs_initialized?
    !@global_sso_orgs.nil? && @global_sso_orgs.is_a?(Array)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def global_sso_app_payload
    return {} unless logged_in?

    if !global_sso_orgs_initialized?
      initialize_global_sso_prompt_for_react
    end

    {
      sso_organizations: global_sso_orgs_payload,
      current_sso_orgs_match_dismissed_cookie: current_sso_orgs_match_dismissed_cookie?
    }
  end
end
