# typed: false
# frozen_string_literal: true

module Api::Serializer::CustomRolesDependency
  def custom_role_hash(custom_role, options = {})
    {
      id: custom_role.id,
      name: custom_role.name,
      description: custom_role.description,
      base_role: custom_role.base_role.name,
      permissions: custom_role.custom_role_permissions.pluck(:action) - Permissions::FineGrainedPermissionIm.disabled_fgps(custom_role.owner).map(&:to_s),
      organization: simple_user_hash(custom_role.owner, options),
      created_at: time(custom_role.created_at),
      updated_at: time(custom_role.updated_at)
    }
  end

  def org_role_hash(org_role, options = {})
    {
      id: org_role.id,
      name: org_role.name,
      description: org_role.description,
      permissions: org_role.custom_role_permissions.pluck(:action),
      base_role: org_role.base_role&.name,
      organization: org_role.owner ? simple_user_hash(org_role.owner, options) : nil,
      created_at: time(org_role.created_at),
      updated_at: time(org_role.updated_at)
    }
  end

  def typed_org_role_hash(org_role, options = {})
    {
      id: org_role.id,
      name: org_role.name,
      description: org_role.description,
      permissions: org_role.custom_role_permissions.pluck(:action),
      organization: org_role.owner_type == "Organization" ? simple_user_hash(org_role.owner, options) : nil,
      created_at: time(org_role.created_at),
      updated_at: time(org_role.updated_at),
      source: source_for_role(org_role),
      base_role: org_role.base_role&.name
    }
  end

  def custom_roles_hash(data, options = {})
    custom_roles = data.fetch(:custom_roles, [])

    {}.tap do |h|
      h[:total_count] = data.fetch(:total_count, 0)
      h[:custom_roles] = custom_roles.map { |role| custom_role_hash(role, options) }
    end
  end

  def org_roles_hash(data, options = {})
    roles = data.fetch(:roles, [])

    {}.tap do |h|
      h[:total_count] = data.fetch(:total_count, 0)
      h[:roles] = roles.map do |role|
        typed_org_role_hash(role, options)
      end
    end
  end

  def user_role_assignment_hash(data, options = {})
    users = data.fetch(:users, [])
    assignments = data.fetch(:assignments, [])

    assignments_hash = users.map do |user|
      hash = simple_user_hash(user, options)
      role_assignments = assignments[user.id]

      hash.update(role_assignment_hash(role_assignments, options))
    end
    assignments_hash
  end

  def team_role_assignment_hash(data, options = {})
    teams = data.fetch(:teams, [])
    assignments = data.fetch(:assignments, [])

    assignments_hash = teams.map do |team|
      hash = team_hash(team, options)
      role_assignments = assignments[team.id]

      hash.update(role_assignment_hash(role_assignments, options))
    end
    assignments_hash
  end

  def role_assignment_hash(role_assignments, options = {})
    direct_exists = false
    indirect_assignments = 0
    assignment_hash = {}
    teams = []

    role_assignments.each do |assignment|
      if assignment.direct?
        direct_exists = true
        next
      end
      if !assignment.through.nil?
        teams << team_simple_hash(assignment.through, options)
      end
      indirect_assignments += 1
    end

    if !teams.empty?
      assignment_hash.update({ inherited_from: teams.uniq })
    end

    assignment_hash.update(assignment_type_hash(direct_exists, indirect_assignments))

    assignment_hash
  end

  def typed_enterprise_role_hash(enterprise_role, options = {})
    {
      id: enterprise_role.id,
      name: enterprise_role.name,
      description: enterprise_role.description,
      permissions: enterprise_role.custom_role_available_permissions.pluck(:action),
      enterprise: enterprise_role.owner_type == "Business" ? business_hash(enterprise_role.owner, options) : nil,
      created_at: time(enterprise_role.created_at),
      updated_at: time(enterprise_role.updated_at),
      source: source_for_role(enterprise_role)
    }
  end

  def enterprise_roles_hash(data, options = {})
    roles = data.fetch(:roles, [])

    {
      total_count: data.fetch(:total_count, 0),
      roles: roles.map { |role| typed_enterprise_role_hash(role, options) }
    }
  end

  def enterprise_user_role_assignment_hash(data, options = {})
    role_assignments = data.fetch(:role_assignments, [])

    role_assignments.map do |role_assignment|
      assignments = role_assignment[:assignments]

      hash = simple_user_hash(role_assignment[:user], options)
      hash.update(enterprise_role_assignment_hash(assignments, options))
    end
  end

  def enterprise_role_assignment_hash(assignments, options = {})
    direct_exists = false
    indirect_assignments = 0
    assignment_hash = {}
    teams = []

    assignments.each do |assignment|
      if assignment[:directly_assigned]
        direct_exists = true
        next
      end

      assignment[:indirect_assignments].each do |team|
        teams << business_team_hash(team, options)
        indirect_assignments += 1
      end
    end

    if !teams.empty?
      assignment_hash.update({ inherited_from: teams.uniq })
    end

    assignment_hash.update(assignment_type_hash(direct_exists, indirect_assignments))

    assignment_hash
  end

  private

  def assignment_type_hash(direct_exists, indirect_assignments)
    if direct_exists
      if indirect_assignments > 0
        ## mixed means the role is BOTH directly assigned to the actor and inherited from a team
        { assignment: "mixed" }
      else
        ## direct means the role is ONLY directly assigned to the actor
        { assignment: "direct" }
      end
    else
      ## indirect means the role is ONLY inherited from a team
      { assignment: "indirect" }
    end
  end

  def source_for_role(role)
    case role.source
    when "Business"
      "Enterprise"
    else
      role.source
    end
  end
end
