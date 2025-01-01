# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesUserPermissionsComponent < ApplicationComponent
  include AvatarHelper
  include CodespacesHelper

  attr_reader :organization, :users, :teams

  def initialize(organization:, users: [], teams: [], flash_error: nil)
    @organization = organization
    @users = users
    @teams = teams
    @flash_error = flash_error
  end

  def render?
    # only render on dotcom
    GitHub.runtime.dotcom?
  end

  def radio_button_checked?(value)
    organization.organization_codespaces_user_limit == value
  end
end
