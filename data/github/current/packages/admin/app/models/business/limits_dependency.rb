# typed: true
# frozen_string_literal: true

module Business::LimitsDependency
  extend T::Helpers

  requires_ancestor { Business }

  ORGANIZATIONS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 100
  MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE = 1_000

  def new_enterprise_platform_limits_enforced?
    FeatureFlag.vexi.enabled?(
      :enforce_new_enterprise_platform_limits,
      T.cast(self, ::Business),
      default: false
    )
  end

  # Public: The "counter" for the organizations per enterprise limit.
  #
  # Returns Integer.
  def organizations_limit_counter
    organization_ids.size
  end

  # Public: The "counter" for the members per enterprise limit.
  #
  # Returns Integer.
  def members_limit_counter
    user_accounts.size
  end

  # Public: The "counter" for the BusinessTeams per Business limit.
  #
  # Returns Integer.
  def business_teams_limit_counter
    business_teams.size
  end

  # Public: Enforce the organizations per enterprise limit.
  #
  # Raises Business::CannotAddOrganizationError.
  # Returns nothing.
  def enforce_organizations_limit!
    return unless new_enterprise_platform_limits_enforced?

    if organizations_limit_reached?
      raise Business::CannotAddOrganizationError.new(organizations_limit_reached_message)
    end
  end

  # Public: Enforce the members per enterprise limit.
  #
  # new_member_ids - Array of new User IDs that are attempting to be added, if attempting to add members in bulk.
  #
  # Raises Business::CannotAddUserAccountError.
  # Returns nothing.
  def enforce_members_limit!(new_member_ids: [])
    return unless new_enterprise_platform_limits_enforced?

    if members_limit_reached?
      raise Business::CannotAddUserAccountError.new(members_limit_reached_message)
    end

    if new_member_ids.any?
      if members_limit_will_be_exceeded_with?(new_member_ids)
        raise Business::CannotAddUserAccountError.new(members_limit_will_be_exceeded_with_message(new_member_ids))
      end
    end
  end

  def members_limit_will_be_exceeded_with_message(new_member_ids)
    limit = number_with_delimiter(members_per_business_limit)
    new_members_count = number_with_delimiter(new_member_ids.size)
    new_members = "member".pluralize(new_member_ids.size)
    "Adding #{new_members_count} #{new_members} will exceed the limit of #{limit} members for the enterprise."
  end

  # Public: Send any appropriate notifications for the organizations per enterprise limit.
  #
  # Called after an org has been successfully added to an enterprise.
  #
  # Returns nothing.
  def send_organizations_limit_notifications
    return unless new_enterprise_platform_limits_enforced?

    organizations.reload

    if at_organizations_limit?
      BusinessLimitsMailer.at_organizations_limit(self).deliver_later
    elsif send_organizations_soft_limit_notification?
      BusinessLimitsMailer.at_organizations_soft_limit(self).deliver_later
    end
  end

  # Public: Send any appropriate notifications for the members per enterprise limit.
  #
  # Called after a BusinessUserAccount has been successfully created for a Business.
  #
  # Returns nothing.
  def send_members_limit_notifications
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit?
      BusinessLimitsMailer.at_members_limit(self).deliver_later
    elsif send_members_soft_limit_notification?
      BusinessLimitsMailer.at_members_soft_limit(self).deliver_later
    end
  end

  def instrument_organizations_limit_events
    return unless new_enterprise_platform_limits_enforced?

    if at_organizations_limit?
      instrument :organizations_limit_reached, organization_limits_instrumentation_payload
    elsif at_organizations_soft_limit?
      instrument :organizations_limit_warning, organization_limits_instrumentation_payload
    end
  end

  def instrument_members_limit_events
    return unless new_enterprise_platform_limits_enforced?

    if at_members_limit?
      instrument :members_limit_reached, member_limits_instrumentation_payload
    elsif at_members_soft_limit?
      instrument :members_limit_warning, member_limits_instrumentation_payload
    end
  end

  def instrument_business_teams_limit_events
    return unless new_enterprise_platform_limits_enforced?

    if at_business_teams_limit?
      instrument :enterprise_teams_limit_reached, business_teams_limits_instrumentation_payload
    elsif at_business_teams_soft_limit?
      instrument :enterprise_teams_limit_warning, business_teams_limits_instrumentation_payload
    end
  end

  private

  def send_organizations_soft_limit_notification?
    return false if organizations_limit_reached? || !organizations_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # and then every ORGANIZATIONS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE orgs over the soft limit.
    at_organizations_soft_limit? || organizations_limit_counter % ORGANIZATIONS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def send_members_soft_limit_notification?
    return false if members_limit_reached? || !members_soft_limit_reached?

    # Send a notification exactly when the soft limit is reached,
    # and then every MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE members over the soft limit.
    at_members_soft_limit? || members_limit_counter % MEMBERS_SOFT_LIMIT_NOTIFICATION_STEP_SIZE == 0
  end

  def organization_limits_instrumentation_payload
    {
      limit: organizations_limit,
      count: organizations_limit_counter,
    }
  end

  def member_limits_instrumentation_payload
    {
      limit: members_limit,
      count: members_limit_counter,
    }
  end

  def business_teams_limits_instrumentation_payload
    {
      limit: business_teams_limit,
      count: business_teams_limit_counter,
    }
  end
end
