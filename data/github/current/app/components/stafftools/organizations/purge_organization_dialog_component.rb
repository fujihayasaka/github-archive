# typed: true
# frozen_string_literal: true

class Stafftools::Organizations::PurgeOrganizationDialogComponent < ApplicationComponent
  include SettingsHelper

  attr_reader :organization, :with_show_button

  def initialize(organization:, with_show_button: false)
    @organization = organization
    @with_show_button = with_show_button
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_business_environment?
    true
  end

  def login
    organization.display_login
  end

  def soft_deleted_at
    return nil unless !!organization&.soft_deleted?

    organization.soft_deleted_at
  end

  def organization_id
    organization.id
  end
end
