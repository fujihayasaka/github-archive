# typed: true
# frozen_string_literal: true

class EditRepositories::Pages::RoleDetailsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Orgs::RolesHelper
  attr_reader :organization, :repository
end
