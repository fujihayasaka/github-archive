# typed: true
# frozen_string_literal: true

# Run when an org admin enables the 2FA requirement on an org.
#
# Removes: - Members that do not have 2FA enabled.
#          - Outside collaborators that do not have 2fa enabled.
#          - Billing managers that do not have 2fa enabled.
class EnforceTwoFactorRequirementOnOrganizationJob < ApplicationJob
  queue_as :enforce_two_factor_requirement

  attr_reader :actor, :organization, :status

  class InvalidActor < StandardError; end

  before_enqueue do |job|
    # Create a JobStatus for the job being enqueued.
    org = job.arguments.first
    status = JobStatus.create(id: EnforceTwoFactorRequirementOnOrganizationJob.job_id(org), ttl: 4.hours)
  end

  def self.job_id(organization)
    "enforce-two-factor-requirement-on-organization_#{organization.id}"
  end

  def self.status(organization)
    JobStatus.find(EnforceTwoFactorRequirementOnOrganizationJob.job_id(organization))
  end

  def self.status!(organization)
    JobStatus.find!(EnforceTwoFactorRequirementOnOrganizationJob.job_id(organization))
  end

  def self.clear_status!(organization)
    # clears the JobStatus in KV (development only).  this prevents caching issues when changing settings rapidly for
    # testing.
    return unless Rails.env.development?
    status(organization)&.destroy
  end

  def initialize(*arguments, disallowed_methods: [])
    @organization = arguments[0]
    @actor = arguments[1]
    @disallowed_methods = disallowed_methods

    super(@organization, @actor, disallowed_methods: @disallowed_methods)
  end

  def perform(organization, actor, disallowed_methods: [])
    raise ArgumentError, "organization cannot be nil" if organization.nil?
    raise ArgumentError, "actor cannot be nil" if actor.blank?
    @disallowed_methods = disallowed_methods

    @organization = organization
    @actor = actor
    @disallowed_methods = disallowed_methods
    @status = EnforceTwoFactorRequirementOnOrganizationJob.status!(organization)

    if Rails.env.development?
      # avoids race conditions between job enqueuing and the page load of settings/security
      sleep 1
    end

    revert_because_failure = T.let(true, T::Boolean)
    failed_because_of_enterprise_team_member = T.let(false, T::Boolean)
    existing_disallowed_methods = organization.get_two_factor_disallowed_methods!

    begin
      status.track do
        validate_actor!
        with_write do
          organization.enable_two_factor_requirement(log_event: true, actor: actor) do
            notify_users_requirement_and_methods_enforced
            remove_affiliated_users_with_two_factor_noncompliance
          end

          if organization.can_disallow_two_factor_methods?
            if @disallowed_methods.any?
              @disallowed_methods.each do |method|
                organization.add_disallowed_two_factor_method(method: method, actor: actor,
                  log_event: !organization.insecure_two_factor_methods_disallowed?
                )
              end
            else
              organization.clear_disallowed_two_factor_methods(actor: actor,
                log_event: organization.insecure_two_factor_methods_disallowed?
              )
            end
          end
        end
        revert_because_failure = false

        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:enabled"])
      end
    rescue Organization::UnableToRemoveEnterpriseTeamMemberError => e
      failed_because_of_enterprise_team_member = true
    ensure
      if revert_because_failure
        with_write do
          organization.disable_two_factor_requirement(actor: actor)

          # reset disallowed methods if they could have been changed - clear and re-add each existing method disallowed
          if organization.can_disallow_two_factor_methods?
            existing_disallowed_methods.each do |method|
              organization.add_disallowed_two_factor_method(method: method, actor: actor, log_event: false)
            end
          end
        end

        OrganizationMailer.failed_two_factor_enforcement(actor, organization, enterprise_team_member_removal_failure: failed_because_of_enterprise_team_member).deliver_now!
        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:failed"])
      end
    end
  end

  # Only removes the users necessary for security
  # is members_without_2fa_allowed-aware so no-op on members or managers if members_without_2fa_allowed
  # always removes outside collaborators until https://github.com/github/authorization/issues/4526
  def remove_affiliated_users_with_two_factor_noncompliance(send_notification: true)
    # move this line back under the early return after https://github.com/github/authorization/issues/4526
    remove_outside_collaborators_with_two_factor_noncompliance(send_notification: send_notification)

    return if organization.members_without_2fa_allowed?
    remove_members_with_two_factor_noncompliance(send_notification: send_notification)
    remove_billing_managers_with_two_factor_noncompliance
  end

  def validate_actor!
    # Site admins may enable 2FA requirement on an org if there is at least
    # one org admin with 2FA enabled.
    return if actor.site_admin? && organization.can_two_factor_requirement_be_enabled? &&
      (@disallowed_methods.empty? || organization.can_disallow_two_factor_methods?)

    unless organization.adminable_by?(actor) && (
      # Only check if actor is a User. When enabling 2FA on an organization
      # after being added to a business we pass the organization as the actor.
      !actor.user? || (actor.two_factor_authentication_enabled? &&
        !actor.has_any_given_2fa_methods_configured?(@disallowed_methods))
    )
      raise InvalidActor.new(actor)
    end
  end

  private

  def event_prefix
    :org
  end

  def event_payload
    {
      actor: actor,
      actor_id: actor.id,
    }.merge(event_context)
  end

  def event_context(prefix: event_prefix)
    organization.event_context(prefix: prefix)
  end

  def remove_members_with_two_factor_noncompliance(send_notification: true)
    organization.members_with_two_factor_disabled.find_each do |user|
      organization.remove_member!(
        user,
        send_notification: send_notification,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end

    return if @disallowed_methods.empty?

    organization.members.two_factor_enabled.find_each do |user|
      if user.has_any_given_2fa_methods_configured?(@disallowed_methods)
        organization.remove_member!(
          user,
          send_notification: send_notification,
          reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
        )
        create_in_app_notification(user)
      end
    end
  end

  def remove_outside_collaborators_with_two_factor_noncompliance(send_notification: true)
    organization.outside_collaborators_with_two_factor_disabled.find_each do |user|
      organization.remove_outside_collaborator(
        user,
        send_notification: send_notification,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end

    return if @disallowed_methods.empty?

    organization.outside_collaborators.two_factor_enabled.find_each do |user|
      if user.has_any_given_2fa_methods_configured?(@disallowed_methods)
        organization.remove_outside_collaborator(
          user,
          send_notification: send_notification,
          reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
        )
        create_in_app_notification(user)
      end
    end
  end

  def remove_billing_managers_with_two_factor_noncompliance
    organization.billing_managers_with_two_factor_disabled.find_each do |user|
      organization.billing.remove_manager(
        user,
        actor: actor,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end

    return if @disallowed_methods.empty?

    organization.members.two_factor_enabled.find_each do |user|
      if user.has_any_given_2fa_methods_configured?(@disallowed_methods)
        organization.billing.remove_manager(
          user,
          actor: actor,
          reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
        )
        create_in_app_notification(user)
      end
    end
  end

  # restore commented collaborator lines after https://github.com/github/authorization/issues/4526
  def notify_users_requirement_and_methods_enforced
    # rubocop:disable Layout/CommentIndentation

    return unless organization.members_without_2fa_allowed?

    no_2fa_members = organization.members_with_two_factor_disabled
    no_2fa_billing = organization.billing_managers_with_two_factor_disabled
    # no_2fa_collaborators = organization.outside_collaborators_with_two_factor_disabled

    no_2fa_members.each do |user|
      OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "member of").deliver_later
      create_in_app_notification(user)
    end

    no_2fa_billing.each do |user|
      OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "billing manager of").deliver_later
      create_in_app_notification(user)
    end

    # no_2fa_collaborators.each do |user|
    #   OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "collaborator within").deliver_later
    #   create_in_app_notification(user)
    # end

    return if @disallowed_methods.empty? || !organization.can_disallow_two_factor_methods?

    disallowed_method_admins = organization.admins_with_two_factor_enabled
      .filter { |a| a.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    disallowed_method_billing = organization.billing_managers_with_two_factor_enabled
      .filter { |b| b.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    disallowed_method_members = organization.members_with_two_factor_enabled
      .filter { |m| m.has_any_given_2fa_methods_configured?(@disallowed_methods) }
      .filter { |m| !disallowed_method_admins.include?(m) } # avoid duplicate notifications to admins, who are also members
    # disallowed_method_collaborators = organization.outside_collaborators.two_factor_enabled
    #  .filter { |c| c.has_any_given_2fa_methods_configured?(@disallowed_methods) }

    disallowed_method_admins.each do |user|
      OrganizationMailer.insecure_two_factor_method_enforcement_member_notification(user, organization, "an admin of").deliver_later
    end

    disallowed_method_billing.each do |user|
      OrganizationMailer.insecure_two_factor_method_enforcement_member_notification(user, organization, "a billing manager of").deliver_later
    end

    disallowed_method_members.each do |user|
      OrganizationMailer.insecure_two_factor_method_enforcement_member_notification(user, organization, "a member of").deliver_later
    end

    # disallowed_method_collaborators.each do |user|
    #   OrganizationMailer.insecure_two_factor_method_enforcement_member_notification(user, organization, "a collaborator within").deliver_later
    # end

    # rubocop:enable Layout/CommentIndentation
  end

  def create_in_app_notification(user)
    Organization::RemovedMemberNotification.new(organization, user).add_two_factor_requirement_non_compliance
  end
end
