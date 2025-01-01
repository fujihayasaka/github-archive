# typed: true
# frozen_string_literal: true

class Organizations::TransferredToBusinessNoticeComponent < ApplicationComponent
  NOTICE_NAME = "business_org_transfer"

  def initialize(organization:)
    @organization = organization
  end

  def render?
    show_notice?
  end

  private

  attr_reader :organization

  def show_notice?
    return false if GitHub.single_business_environment?
    return false unless logged_in?
    return false if dismissed_notice?
    return false unless organization_adminable_by_current_user?
    return false unless organization.business

    transfer.present?
  end

  def dismissed_notice?
    current_user.dismissed_organization_notice?(NOTICE_NAME, organization)
  end

  def dismissal_path
    dismiss_org_notice_path \
      organization,
      input: {
        organizationId: organization.id,
        notice: NOTICE_NAME
      }
  end

  memoize def organization_adminable_by_current_user?
    organization.adminable_by?(current_user)
  end

  memoize def transfer
    BusinessOrganizationTransfer
      .completed
      .where(
        organization: organization,
        to_business: organization.business
      )
      .order(created_at: :desc)
      .first
  end
end
