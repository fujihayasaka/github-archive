# typed: true
# frozen_string_literal: true

module Team::LimitsDependency
  extend T::Helpers

  requires_ancestor { Team }

  MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000

  def new_enterprise_platform_limits_enforced?
    self.organization&.new_enterprise_platform_limits_enforced?
  end

  # Public: The members per Team limit configurable per Organization.
  #
  # Returns Integer.
  def members_per_org_team_limit
    self.organization&.members_per_org_team_limit
  end

  # Public: The members per Team soft limit configurable per Organization.
  #
  # Returns Integer.
  def members_per_org_team_soft_limit
    self.organization&.members_per_org_team_soft_limit
  end

  # Public: The "counter" for the members per org team limit.
  #
  # Returns Integer.
  def members_limit_counter
    member_ids.size
  end

  # Public: Send any appropriate notifications for the members per org team limit.
  #
  # Called after members have been successfully added to the team.
  #
  # members_count_was - Integer indicating the members count before the addition of new members.
  #
  # Returns nothing.
  def send_members_limit_notifications(members_count_was:)
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit? || just_exceeded_members_limit?(members_count_was)
      TeamLimitsMailer.at_members_limit(self).deliver_later
    elsif send_members_soft_limit_notification?(members_count_was)
      TeamLimitsMailer.at_members_soft_limit(self).deliver_later
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

  def send_members_soft_limit_notification?(members_count_was)
    return false if members_limit_reached? || !members_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # or if it was just exceeded when adding members in bulk,
    # and then every MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE members over the soft limit.
    at_members_soft_limit? ||
    just_exceeded_members_soft_limit?(members_count_was) ||
    members_limit_counter % MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def members_limits_instrumentation_payload
    {
      limit: members_limit,
      count: members_limit_counter,
    }
  end
end
