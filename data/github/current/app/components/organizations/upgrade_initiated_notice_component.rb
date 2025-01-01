# typed: true
# frozen_string_literal: true

class Organizations::UpgradeInitiatedNoticeComponent < ApplicationComponent

  def initialize(organization:, viewer:)
    @organization = organization
    @viewer = viewer
  end

  private

  def render?
    return unless @organization.upgrade_to_enterprise_in_progress?

    parent_business = @organization.upgrade_to_enterprise_in_progress

    parent_business.organization_upgrade_initiated? && parent_business.adminable_by?(@viewer)
  end
end
