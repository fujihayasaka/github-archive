# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupController < ApplicationController
  include Signups::CustomContentDependency

  PAGE_SIZE = 7

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::NotificationsEntries

  before_action :login_required
  before_action :dotcom_required
  before_action :feature_flag_enabled?
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout :signups_layout

  javascript_bundle "signup"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"

  def index
    if !params.key?(:new) && user_has_entities?
      render "signup/select_org_business", locals: {
        custom_page_param: custom_page_param,
        contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param)
      }
    else
      render "signup/new_org_business", locals: {
        custom_page_param: custom_page_param,
        contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param)
      }
    end
  end

  private

  memoize def user_owned_orgs
    current_user.owned_or_billing_manager_organizations
  end

  memoize def user_owned_businesses
    current_user.businesses(membership_type: :admin)
  end

  def user_has_entities?
    user_owned_orgs.any? || user_owned_businesses.any?
  end

  def feature_flag_enabled?
    unless FeatureFlag.vexi.enabled?(:dfd_get_started_with_copilot, current_user, default: false)
      render_404
    end
  end

  def signups_layout
    "layouts/signups_rebrand"
  end
end
