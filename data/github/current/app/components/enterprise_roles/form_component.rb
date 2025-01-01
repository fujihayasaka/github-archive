# typed: strict
# frozen_string_literal: true

class EnterpriseRoles::FormComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(T.nilable(Business)) }
  attr_reader :owner

  sig { returns(T.nilable(EnterpriseRole)) }
  attr_reader :role

  sig { returns(T::Hash[String, Integer]) }
  attr_reader :assignment_counts

  sig do
    params(
      owner: Business,
      role: T.nilable(EnterpriseRole),
      assignment_counts: T::Hash[String, Integer],
    ).void
  end
  def initialize(owner:, role: nil, assignment_counts: {})
    @owner = owner
    @role = role
    @assignment_counts = assignment_counts
    @base_role = T.let(role&.base_role, T.nilable(Role))
  end

  sig { returns(T::Array[EnterpriseFgpMetadata]) }
  memoize def available_fgps
    EnterpriseRoleFgps.new.available_fgps(owner)
  end

  # Only applicable when editing a custom role.
  # Returns a list of selected FGPs that already exist on the role.
  #
  # Note: Does not update as user adds FGPs
  sig { returns(T::Array[String]) }
  memoize def selected_fgps
    return [] unless role

    T.must(role).permissions.pluck(:action)
  end

  sig { returns(String) }
  def form_url
    if new_page?
      enterprise_roles_path(owner)
    else
      enterprise_role_path(owner, role)
    end
  end

  sig { returns(Integer) }
  def role_user_count
    assignment_counts["User"] || 0
  end

  sig { returns(Integer) }
  def role_team_count
    assignment_counts["BusinessTeam"] || 0
  end

  sig { returns(T::Boolean) }
  def new_page?
    role.nil?
  end

  sig { returns(String) }
  def heading
    new_page? ? "Create custom role" : "Edit custom role"
  end
end
