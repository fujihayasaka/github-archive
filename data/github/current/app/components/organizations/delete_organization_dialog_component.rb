# typed: true
# frozen_string_literal: true

class Organizations::DeleteOrganizationDialogComponent < ApplicationComponent
  include SettingsHelper

  attr_reader :organization

  def initialize(organization:)
    @organization = organization
  end

  private

  def submit_button_text
    if GitHub.billing_enabled? && organization.business.blank?
      "Cancel plan and delete the organization"
    else
      "Delete the organization"
    end
  end

  def deletion_path
    organization_settings_soft_deletion_path(organization)
  end

  def deletion_method
    :post
  end
end
