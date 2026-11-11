# typed: true
# frozen_string_literal: true

module BusinessTeam::LimitsDependency
  extend T::Helpers

  requires_ancestor { BusinessTeam }

  BUSINESS_TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000
  MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000
  ORGANIZATION_ASSIGNMENTS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 100

  def new_enterprise_platform_limits_enforced?
    FeatureFlag.vexi.enabled?(
      :enforce_new_enterprise_platform_limits,
      T.must(business),
      default: false
    )
  end

  # Public: The "counter" for the members per enterprise team limit.
  #
  # Returns Integer.
  def members_limit_counter
    members_count
  end

  # Public: The "counter" for the organization assignments per enterprise team limit.
  #
  # Returns Integer.
  def organization_assignments_limit_counter
    selected_organizations.count
  end

  # Public: Send any appropriate notifications for the BusinessTeams per Business limit.
  #
  # Called after a BusinessTeam has been successfully created within a Business.
  #
  # Returns nothing.
  def send_business_teams_limit_notifications
    return unless new_enterprise_platform_limits_enforced?

    if T.must(business).at_business_teams_limit?
      BusinessTeamLimitsMailer.at_business_teams_limit(T.must(business)).deliver_later
    elsif send_business_teams_soft_limit_notification?
      BusinessTeamLimitsMailer.at_business_teams_soft_limit(T.must(business)).deliver_later
    end
  end

  # Public: Send any appropriate notifications for the members per BusinessTeam limit.
  #
  # Called after members have been successfully added to the BusinessTeam.
  #
  # members_count_was - Integer indicating the members count before the addition of new members.
  #
  # Returns nothing.
  def send_members_limit_notifications(members_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit? || just_exceeded_members_limit?(members_count_was)
      BusinessTeamLimitsMailer.at_members_limit(self).deliver_later
    elsif send_members_soft_limit_notification?(members_count_was)
      BusinessTeamLimitsMailer.at_members_soft_limit(self).deliver_later
    end
  end

  # Public: Send any appropriate notifications for the organization assignments per BusinessTeam limit.
  #
  # Called after an Organization has been successfully assigned to the BusinessTeam.
  #
  # organization_assignments_count_was - Integer indicating the organization assignments count before the
  # assignment of new organizations.
  #
  # Returns nothing.
  def send_organization_assignments_limit_notifications(organization_assignments_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_organization_assignments_limit? || just_exceeded_organization_assignments_limit?(organization_assignments_count_was)
      BusinessTeamLimitsMailer.at_organization_assignments_limit(self).deliver_later
    elsif send_organization_assignments_soft_limit_notification?(organization_assignments_count_was)
      BusinessTeamLimitsMailer.at_organization_assignments_soft_limit(self).deliver_later
    end
  end

  def instrument_members_limit_events(members_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit? || just_exceeded_members_limit?(members_count_was)
      instrument :members_limit_reached, members_limits_instrumentation_payload
    elsif at_members_soft_limit? || just_exceeded_members_soft_limit?(members_count_was)
      instrument :members_limit_warning, members_limits_instrumentation_payload
    end
  end

  def instrument_organization_assignments_limit_events(organization_assignments_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_organization_assignments_limit? || just_exceeded_organization_assignments_limit?(organization_assignments_count_was)
      instrument :organization_assignments_limit_reached, organization_assignments_limits_instrumentation_payload
    elsif at_organization_assignments_soft_limit? || just_exceeded_organization_assignments_soft_limit?(organization_assignments_count_was)
      instrument :organization_assignments_limit_warning, organization_assignments_limits_instrumentation_payload
    end
  end

  private

  def send_business_teams_soft_limit_notification?
    if T.must(business).business_teams_limit_reached? || !T.must(business).business_teams_soft_limit_reached?
      return false
    end

    # Send a notification exactly when the soft limit is reached,
    # and then every BUSINESS_TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE BusinessTeams over the soft limit.
    T.must(business).at_business_teams_soft_limit? ||
    T.must(business).business_teams_limit_counter % BUSINESS_TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def just_exceeded_members_limit?(members_count_was)
    members_count_was < members_limit && members_limit_reached?
  end

  def just_exceeded_members_soft_limit?(members_count_was)
    members_count_was < members_soft_limit && members_soft_limit_reached?
  end

  def send_members_soft_limit_notification?(members_count_was)
    return false if members_limit_reached? || !members_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # or if it was just exceeded when adding members in bulk,
    # and then every MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE members over the soft limit.
    at_members_soft_limit? ||
    just_exceeded_members_soft_limit?(members_count_was) ||
    members_limit_counter % MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def just_exceeded_organization_assignments_limit?(organization_assignments_count_was)
    organization_assignments_count_was < organization_assignments_limit && organization_assignments_limit_reached?
  end

  def just_exceeded_organization_assignments_soft_limit?(organization_assignments_count_was)
    organization_assignments_count_was < organization_assignments_soft_limit && organization_assignments_soft_limit_reached?
  end

  def send_organization_assignments_soft_limit_notification?(organization_assignments_count_was)
    return false if organization_assignments_limit_reached? || !organization_assignments_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # or if it was just exceeded when adding organization assignments in bulk,
    # and then every ORGANIZATION_ASSIGNMENTS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE assignments over the soft limit.
    at_organization_assignments_soft_limit? ||
    just_exceeded_organization_assignments_soft_limit?(organization_assignments_count_was) ||
    organization_assignments_limit_counter % ORGANIZATION_ASSIGNMENTS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def instrument_business_teams_per_business_limit_events
    T.must(business).instrument_business_teams_limit_events
  end

  def members_limits_instrumentation_payload
    {
      business: business,
      limit: members_limit,
      count: members_limit_counter,
    }
  end

  def organization_assignments_limits_instrumentation_payload
    {
      business: business,
      limit: organization_assignments_limit,
      count: organization_assignments_limit_counter,
    }
  end
end
