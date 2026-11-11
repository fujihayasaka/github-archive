# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityEnterpriseTrialBannerComponent < ApplicationComponent
  include SvgHelper

  attr_reader :notice_key, :feature_name, :header_text, :description_text, :learn_more_path, :user, :organization

  def initialize(user:, organization:, feature_name:, description_text:, notice_key:, learn_more_path:, header_text: "")
    @organization     = organization
    @notice_key       = notice_key
    @feature_name     = feature_name
    @header_text      = header_text
    @description_text = description_text
    @learn_more_path  = learn_more_path
    @user             = user
  end

  def render?
    return false unless organization
    return false unless user
    return false unless organization.adminable_by?(user)

    organization.plan.free? || organization.plan.business? || organization.eligible_for_legacy_upsell?
  end

  def render_banner?
    !user.dismissed_notice?(notice_key)
  end

  def trial_path
    if Billing::EnterpriseCloudTrial.eligible?(organization)
      new_org_enterprise_trial_path(organization.display_login)
    else
      new_organization_path(plan: "business_plus")
    end
  end
end
