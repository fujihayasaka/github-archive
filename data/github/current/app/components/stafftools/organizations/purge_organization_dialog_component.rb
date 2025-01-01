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

  def login
    # We really want the login, not display_login, as we need the tenant suffix on proxima stafftools.
    organization.login
  end

  def soft_deleted_at
    return nil unless !!organization&.soft_deleted?

    organization.soft_deleted_at
  end

  def organization_id
    organization.id
  end

  memoize def disabled?
    !helpers.stafftools_action_authorized?(controller: Stafftools::UsersController, action: :destroy)
  end
end
