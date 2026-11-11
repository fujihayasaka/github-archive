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
    helper_method :dismissed_sso_org_ids
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

  def dismissed_sso_org_ids
    return [] unless logged_in?

    dismissed_cookie = cookies[DISMISSED_SSO_ORGS_COOKIE_NAME]
    return [] if dismissed_cookie.blank?

    begin
      dismissed_org_ids = JSON.parse(dismissed_cookie)
      return [] unless dismissed_org_ids.is_a?(Array)

      # Return org IDs that have been dismissed
      dismissed_org_ids.map(&:to_i)
    rescue JSON::ParserError
      # If cookie is malformed, delete it and return empty array
      cookies.delete(DISMISSED_SSO_ORGS_COOKIE_NAME, domain: cookie_domain)
      []
    end
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def dismissed_sso_orgs
    global_sso_orgs_payload.select { |org| dismissed_sso_org_ids.include?(org[:id].to_i) }
  end

  sig { returns(T::Array[T::Hash[Symbol, String]]) }
  def undismissed_sso_orgs
    return [] unless logged_in?
    global_sso_orgs_payload - dismissed_sso_orgs
  end

  sig { returns(T::Boolean) }
  def show_global_sso_banner?
    return false unless global_sso_banner_enabled_for_current_page?
    return false if @skip_global_sso_banner_rendering

    # show the banner if there are any undismissed SSO orgs
    undismissed_sso_orgs.any?
  end

  sig { returns(T::Boolean) }
  def global_sso_banner_enabled_for_current_page?
    return false unless logged_in?
    global_sso_orgs_initialized?
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
      current_sso_orgs_match_dismissed_cookie: undismissed_sso_orgs.empty?
    }
  end
end
