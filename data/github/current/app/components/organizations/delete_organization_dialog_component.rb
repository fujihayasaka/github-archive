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
    if organization.can_soft_delete?(current_user)
      organization_settings_soft_deletion_path(organization)
    else
      organization_path(organization)
    end
  end

  def deletion_method
    if organization.can_soft_delete?(current_user)
      :post
    else
      :delete
    end
  end
end
