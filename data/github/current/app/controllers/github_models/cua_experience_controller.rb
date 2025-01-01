# typed: true
# frozen_string_literal: true

class GitHubModels::CuaExperienceController < ApplicationController
  include GitHub::Memoizer

  before_action :login_required
  before_action :require_feature
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries

  CSP_EXCEPTIONS = {
    connect_src: [
      GitHub.models_gateway_url,
    ],
    img_src: [
      SecureHeaders::PolicyManagement::DATA_PROTOCOL,
    ],
  }.freeze
  before_action :add_csp_exceptions

  def self.react_bundle_name
    "github-models-cua"
  end

  def index
    context_region_preset :models

    auth_token = Rails.env.development? ? "Bearer #{ENV.fetch("GITHUB_TOKEN", "UNKNOWN")}" : "UNKNOWN"

    # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    if Rails.env.production?
      user = T.must_because(user_session.user) { "we expect user_session to always have a user" }
      new_access = neutron_app.grant(user, { user_session: user_session })
      token, _ = new_access.redeem(extended_expiry: true)
      encrypted = simple_box.encrypt(token)
      auth_token = "GitHub-Bearer #{Base64.urlsafe_encode64(encrypted)}"
    end

    render_react_html(
      title: "GitHub Models CUA",
      app_payload_generator: -> { { auth_token: auth_token } },
      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
      }
    )
  end

  private

  sig { returns(Integration) }
  memoize def neutron_app
    ::Apps::Privileged.integration(:neutron)
  end

  sig { returns(RbNaCl::SimpleBox) }
  memoize def simple_box
    key = T.must_because(GitHub.models_simple_box_key) { "must have an encryption key set" }

    RbNaCl::SimpleBox.from_secret_key(key.b)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def require_feature
    render_404 unless feature_enabled_globally_or_for_current_user?(:models_cua)
  end
end
