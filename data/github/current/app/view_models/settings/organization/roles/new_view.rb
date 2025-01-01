# typed: true
# frozen_string_literal: true

class Settings::Organization::Roles::NewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Orgs::CustomRoleFormHelper

  include UrlHelpers

  attr_reader :base_role_fgps, :organization, :role

  delegate :base_role, :title_for, :icon_for, to: :base_role_fgps
end
