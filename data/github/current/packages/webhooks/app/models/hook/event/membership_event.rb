# typed: true
# frozen_string_literal: true

class Hook::Event::MembershipEvent < Hook::Event
  supports_targets Organization, Business, Integration
  description "Team membership added or removed."

  event_attr :member_id, :member_login, :organization_id, :action, required: true
  event_attr :actor_id, :team_id, :team_name

  # Membership events are often triggered as a result
  # of cascading deletes. We can handle most of these
  # cases gracefully. But, if the organization itself has
  # been deleted we cannot deliver this event since the
  # associated hooks have also been deleted.
  def deliverable?
    !target_organization_deleted?
  end

  def target_organization
    return @org if defined?(@org)

    @org ||= Organization.find(organization_id)
  rescue ActiveRecord::RecordNotFound => e
    if action == :removed
      # RecordNotFound is expected when membership
      # removed as a result of an org deletion.
      @org_deleted = true
      @org = nil
    else
      raise e
    end
  end

  def target_organization_deleted?
    !target_organization && @org_deleted
  end

  def team
    return @team if defined?(@team)

    @team = team_id && Team.find(team_id)
  rescue ActiveRecord::RecordNotFound => e
    if action == :removed
      # RecordNotFound is expected when membership
      # removed as a result of team deletion.
      @team_deleted = true
      @team = nil
    else
      raise e
    end
  end

  def team_deleted?
    !team && @team_deleted
  end

  def member
    return @member if defined?(@member)

    @member = User.find(member_id)
  rescue ActiveRecord::RecordNotFound => e
    if action == :removed
      # RecordNotFound is expected when membership
      # removed as a result of user deletion.
      @member_deleted = true
      @member = nil
    else
      raise e
    end
  end

  def member_deleted?
    !member && @member_deleted
  end

  def actor
    return @actor if defined?(@actor)

    @actor = actor_id.present? ? User.find(actor_id) : target_organization
  rescue ActiveRecord::RecordNotFound => e
    if action == :removed && actor_id == member_id
      # RecordNotFound is expected when membership
      # removed as a result of user deleting their own account.
      @member_deleted_own_account = true
      @actor = nil
    else
      raise e
    end
  end

  def member_deleted_own_account?
    !actor && @member_deleted_own_account
  end

  def action
    attributes[:action].to_sym
  end

  def scope
    team.present? ? :team : :organization
  end
end
