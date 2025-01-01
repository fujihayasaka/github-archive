# typed: strict
# frozen_string_literal: true

class OrgRoles::ActionMenuComponent < ApplicationComponent
  extend T::Sig

  sig { returns(Integer) }
  attr_reader :role_id

  sig { returns(String) }
  attr_reader :role_name

  sig { returns(Integer) }
  attr_reader :role_user_count

  sig { returns(Integer) }
  attr_reader :role_team_count

  sig { returns(String) }
  attr_reader :delete_path

  sig { returns(String) }
  attr_reader :edit_path

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  attr_reader :viewer_permissions

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig do
    params(
      role_id: Integer,
      role_name: String,
      delete_path: String,
      edit_path: String,
      viewer_permissions: T::Hash[Symbol, T::Boolean],
      role_user_count: Integer,
      role_team_count: Integer,
      system_arguments: T.untyped,
    ).void
  end
  def initialize(role_id:, role_name:, delete_path:, edit_path:, viewer_permissions:, role_user_count: 0, role_team_count: 0, **system_arguments)
    @role_id = role_id
    @role_name = role_name
    @delete_path = delete_path
    @edit_path = edit_path
    @viewer_permissions = viewer_permissions
    @role_user_count = role_user_count
    @role_team_count = role_team_count
    @system_arguments = system_arguments
  end
end
