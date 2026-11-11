# typed: true
# frozen_string_literal: true

module Organization::LimitsDependency
  extend T::Helpers

  requires_ancestor { Organization }

  TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000
  MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000

  def new_enterprise_platform_limits_enforced?
    FeatureFlag.vexi.enabled?(
      :enforce_new_enterprise_platform_limits,
      T.cast(self, ::Organization),
      default: false
    ) ||
    self.business&.new_enterprise_platform_limits_enforced?
  end

  # Public: The "counter" for the teams per org limit.
  #
  # Returns Integer.
  def teams_limit_counter
    teams_with_business_teams.size
  end

  # Public: The "counter" for the members per org limit.
  #
  # Returns Integer.
  def members_limit_counter
    members_count
  end

  # Public: Enforce the members per org limit.
  #
  # Raises Organization::UnableToAddMemberDueToMembersLimitError.
  # Returns nothing.
  def enforce_members_limit!
    return unless new_enterprise_platform_limits_enforced?

    if members_limit_reached?
      raise Organization::UnableToAddMemberDueToMembersLimitError.new(members_limit_reached_message)
    end
  end

  # Public: Send any appropriate notifications for the Teams per Organization limit.
  #
  # Called after a Team has been successfully created within an Organization.
  #
  # Returns nothing.
  def send_teams_limit_notifications
    return unless new_enterprise_platform_limits_enforced?

    teams.reload

    if at_teams_limit?
      OrganizationLimitsMailer.at_teams_limit(self).deliver_later
    elsif send_teams_soft_limit_notification?
      OrganizationLimitsMailer.at_teams_soft_limit(self).deliver_later
    end
  end

  def instrument_teams_limit_events
    return unless new_enterprise_platform_limits_enforced?

    if at_teams_limit?
      instrument :teams_limit_reached, teams_limits_instrumentation_payload
    elsif at_teams_soft_limit?
      instrument :teams_limit_warning, teams_limits_instrumentation_payload
    end
  end

  # Public: Send any appropriate notifications for the members per Organization limit.
  #
  # Called after members have been successfully added to the Organization.
  #
  # members_count_was - Integer indicating the members count before the addition of new members.
  #
  # Returns nothing.
  def send_members_limit_notifications(members_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit? || just_exceeded_members_limit?(members_count_was)
      OrganizationLimitsMailer.at_members_limit(self).deliver_later
    elsif send_members_soft_limit_notification?(members_count_was)
      OrganizationLimitsMailer.at_members_soft_limit(self).deliver_later
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

  private

  def just_exceeded_members_limit?(members_count_was)
    members_count_was < members_limit && members_limit_reached?
  end

  def just_exceeded_members_soft_limit?(members_count_was)
    members_count_was < members_soft_limit && members_soft_limit_reached?
  end

  def send_teams_soft_limit_notification?
    return false if teams_limit_reached? || !teams_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # and then every TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE teams over the soft limit.
    at_teams_soft_limit? || teams_limit_counter % TEAMS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
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

  def teams_limits_instrumentation_payload
    {
      limit: teams_limit,
      count: teams_limit_counter,
    }
  end

  def members_limits_instrumentation_payload
    {
      limit: members_limit,
      count: members_limit_counter,
    }
  end
end
