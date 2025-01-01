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

  def initialize(*arguments)
    @organization = arguments[0]
    @actor = arguments[1]

    super(@organization, @actor)
  end

  def perform(organization, actor)
    raise ArgumentError, "organization cannot be nil" if organization.nil?
    raise ArgumentError, "actor cannot be nil" if actor.blank?

    @organization = organization
    @actor = actor
    @status = EnforceTwoFactorRequirementOnOrganizationJob.status!(organization)

    revert_because_failure = T.let(true, T::Boolean)
    failed_because_of_enterprise_team_member = T.let(false, T::Boolean)

    begin
      status.track do
        validate_actor!
        with_write do
          organization.enable_two_factor_requirement(log_event: true, actor: actor) do
            remove_affiliated_users_with_two_factor_disabled
          end
        end
        revert_because_failure = false

        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:enabled"])
      end
    rescue Organization::UnableToRemoveEnterpriseTeamMemberError => e
      failed_because_of_enterprise_team_member = true
    ensure
      if revert_because_failure
        with_write { organization.disable_two_factor_requirement(actor: actor) }

        OrganizationMailer.failed_two_factor_enforcement(actor, organization, enterprise_team_member_removal_failure: failed_because_of_enterprise_team_member).deliver_now!
        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:failed"])
      end
    end
  end

  def remove_affiliated_users_with_two_factor_disabled(send_notification: true)
    return if organization.members_without_2fa_allowed?
    remove_members_with_two_factor_disabled(send_notification: send_notification)
    remove_outside_collaborators_with_two_factor_disabled(send_notification: send_notification)
    remove_billing_managers_with_two_factor_disabled
  end

  def validate_actor!
    # Site admins may enable 2FA requirement on an org if there is at least
    # one org admin with 2FA enabled.
    if organization.can_two_factor_requirement_be_enabled?
      return if actor.site_admin?
    end

    unless organization.adminable_by?(actor) && (
      # Only check if actor is a User. When enabling 2FA on an organization
      # after being added to a business we pass the organization as the actor.
      !actor.user? || actor.two_factor_authentication_enabled?
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

  def remove_members_with_two_factor_disabled(send_notification: true)
    organization.members_with_two_factor_disabled.find_each do |user|
      organization.remove_member!(
        user,
        send_notification: send_notification,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def remove_outside_collaborators_with_two_factor_disabled(send_notification: true)
    organization.outside_collaborators_with_two_factor_disabled.find_each do |user|
      organization.remove_outside_collaborator(
        user,
        send_notification: send_notification,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def remove_billing_managers_with_two_factor_disabled
    organization.billing_managers_with_two_factor_disabled.find_each do |user|
      organization.billing.remove_manager(
        user,
        actor: actor,
        reason: Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def create_in_app_notification(user)
    Organization::RemovedMemberNotification.new(organization, user).add_two_factor_requirement_non_compliance
  end
end
