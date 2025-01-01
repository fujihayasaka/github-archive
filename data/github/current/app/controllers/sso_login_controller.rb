# typed: true
# frozen_string_literal: true

class SsoLoginController < ApplicationController
  include FeatureFlagHelper

  before_action :emu_sso_login_enabled

  layout "layouts/session_authentication"

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: :domain_check,
    key: :sso_login_domain_check_limit_key,
    max: :sso_login_domain_check_limit_max,
    ttl: :sso_login_domain_check_limit_ttl

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:new]

  CAP_OPT_OUT_ACTIONS = %w(new domain_check)

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def new
    render "sso_login/new"
  end

  def domain_check # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      slug = params[:value]

      if slug.match(Business::SLUG_REGEX)
        business = Business.find_by(slug: slug)
        return head :ok if business&.enterprise_managed_user_and_saml_sso_enabled?
      end

      format.html_fragment do
        render body: "Enter a valid enterprise URL", status: 422, content_type: "text/fragment+html"
      end
    end
  end

  private

  def emu_sso_login_enabled
    render_404 unless feature_enabled_for_user_or_current_visitor?(feature_name: :emu_sso_login)
  end

  def sso_login_domain_check_limit_key
    "domain-check:#{request.remote_ip}"
  end

  def sso_login_domain_check_limit_max
    100
  end

  def sso_login_domain_check_limit_ttl
    GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL
  end
end
