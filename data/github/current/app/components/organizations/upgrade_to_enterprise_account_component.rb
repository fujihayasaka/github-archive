# typed: strict
# frozen_string_literal: true

class Organizations::UpgradeToEnterpriseAccountComponent < ApplicationComponent
  extend T::Sig
  DISMISSAL_LENGTH = T.let(3.days, ActiveSupport::Duration)

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(String) }
  attr_reader :location

  sig { params(organization: Organization, location: String).void }
  def initialize(organization:, location: "")
    @organization = organization
    @location = location
  end

  sig { returns(T.nilable(String)) }
  def upgrade_to_enterprise_path
    new_org_enterprise_upgrade_path(organization)
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

  sig { returns(T.nilable(Time)) }
  def dismissal_period
    DISMISSAL_LENGTH.from_now
  end

  sig { returns(String) }
  def notice_name
    "upgrade-ghec-org-to-enterprise-account-dialog-notice"
  end

  sig { returns(T::Boolean) }
  def notice_per_user?
    false
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless organization.present?
    return false unless current_user.present?
    return false unless organization.adminable_by?(current_user)
    return false unless organization.feature_enabled?(:upgrade_to_enterprise_account_dialog)
    return false unless organization.eligible_for_upgrade_to_enterprise?

    !Growth::NoticeDismissal.new(current_user).dismissed_organization_notice?(notice_name, organization_id: T.must(organization.id), per_user: notice_per_user?)
  end
end
