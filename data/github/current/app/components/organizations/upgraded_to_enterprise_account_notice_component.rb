# typed: strict
# frozen_string_literal: true

class Organizations::UpgradedToEnterpriseAccountNoticeComponent < ApplicationComponent
  FAQ_URL = T.let("#{GitHub.help_url}/admin/overview/creating-an-enterprise-account#what-will-happen-after-i-upgrade-my-organization", String)

  sig { returns(Organization) }
  attr_reader :organization

  sig { params(organization: Organization).void }
  def initialize(organization:)
    @organization = organization
  end

  sig { returns(T.nilable(String)) }
  def business_settings_path
    settings_profile_enterprise_path(business)
  end

  sig { returns(T.nilable(String)) }
  def faq_path
    FAQ_URL
  end

  sig { returns(T.nilable(String)) }
  def dialog_background_image
    color_theme_picture_tag(
      {
        light: "modules/site/enterprise/upgrade-to-enterprise-account-light.png",
        dark: "modules/site/enterprise/upgrade-to-enterprise-account-dark.png"
      },
      alt: "Free Upgrade to Enterprise Account Dialog",
      style: "position: absolute; z-index: -1;"
    )
  end

  sig { returns(String) }
  def notice_name
    "upgraded-to-enterprise-account-dialog-notice"
  end

  sig { returns(T::Boolean) }
  def notice_per_user?
    true
  end

  sig { returns(T.nilable(Business)) }
  def business
    organization.business
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless organization.present?
    return false unless current_user.present?
    return false unless business.present?
    return false unless organization.adminable_by?(current_user)
    return false unless T.must(business).owners.include?(current_user)
    return false unless organization.feature_enabled?(:upgraded_to_enterprise_account_notice_dialog)
    return false unless organization.id == T.must(business).upgraded_from_id
    return false unless T.must(business).upgraded_from_plan == "business_plus"
    return false if T.must(business).upgraded_at < 14.days.ago

    !Growth::NoticeDismissal.new(current_user).dismissed_organization_notice?(notice_name, organization_id: organization.id, per_user: notice_per_user?)
  end
end
