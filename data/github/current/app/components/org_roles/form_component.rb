# typed: strict
# frozen_string_literal: true

class OrgRoles::FormComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(T.any(Organization, Business)) }
  attr_reader :owner

  sig { returns(T.nilable(OrganizationRole)) }
  attr_reader :role

  sig { returns(T::Hash[String, Integer]) }
  attr_reader :assignment_counts

  sig { returns(T.nilable(Role)) }
  attr_reader :base_role

  sig do
    params(
      owner: T.any(Organization, Business),
      role: T.nilable(OrganizationRole),
      assignment_counts: T::Hash[String, Integer],
    ).void
  end
  def initialize(owner:, role: nil, assignment_counts: {})
    @owner = owner
    @role = role
    @assignment_counts = assignment_counts
    @base_role = T.let(role&.base_role, T.nilable(Role))
  end

  sig { returns(T::Array[OrgFgpMetadata]) }
  memoize def available_fgps
    OrgRoleFgps.new.available_fgps(owner)
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
      gh_create_org_role_path(owner)
    else
      gh_update_org_role_path(owner, role)
    end
  end

  sig { returns(Integer) }
  def role_user_count
    assignment_counts["User"] || 0
  end

  sig { returns(Integer) }
  def role_team_count
    team_count = assignment_counts["Team"] || 0
    team_count += role_business_team_count if supports_business_teams?
    team_count
  end

  sig { returns(Integer) }
  def role_business_team_count
    assignment_counts["BusinessTeam"] || 0
  end

  sig { returns(T::Array[T::Hash[Symbol, Symbol]]) }
  def repo_fgps
    roles_order = [:triage, :write, :maintain, nil]
    RepoRoleFgps.fgps_payload(owner).values.sort_by { |item| roles_order.index(item[:base_role]) }
  end

  sig { returns(T::Boolean) }
  def new_page?
    role.nil?
  end

  sig { returns(T::Boolean) }
  memoize def supports_business_teams?
    business = owner.is_a?(Business) ? owner : T.cast(owner, Organization).business
    return false unless business

    T.cast(business, Business).enterprise_teams_org_roles_supported?
  end
end
