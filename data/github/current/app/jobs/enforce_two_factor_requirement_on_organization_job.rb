# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Run when an org admin enables the 2FA requirement on an org.
#
# Removes: - Members that do not have 2FA enabled.
#          - Outside collaborators that do not have 2fa enabled.
#          - Billing managers that do not have 2fa enabled.
class EnforceTwoFactorRequirementOnOrganizationJob < ApplicationJob
  queue_as :enforce_two_factor_requirement

  resolve_tenant_context do |organization|
    organization.business
  end

  attr_reader :actor, :organization, :status

  class InvalidActor < StandardError; end

  before_enqueue do |job|
    # Create a JobStatus for the job being enqueued.
    org = job.arguments.first
    status = Organization::JobStatus.create(id: EnforceTwoFactorRequirementOnOrganizationJob.job_id(org), ttl: 4.hours)
  end

  def self.prefix
    "enforce-two-factor-requirement-on-organization"
  end

  def self.job_id(organization)
    "#{prefix}_#{organization.id}"
  end

  def self.status(organization)
    Organization::JobStatus.find(EnforceTwoFactorRequirementOnOrganizationJob.job_id(organization))
  end

  def self.status!(organization)
    Organization::JobStatus.find!(EnforceTwoFactorRequirementOnOrganizationJob.job_id(organization))
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
    existing_required = organization.two_factor_requirement_enabled?
    existing_disallowed_methods = organization.get_two_factor_disallowed_methods!

    begin
      status.track do
        validate_actor!
        with_write do
          organization.enable_two_factor_requirement(log_event: true, actor: actor) do
            notify_users_requirement_and_methods_enforced
            remove_outside_collaborators_with_two_factor_noncompliance
          end

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
        revert_because_failure = false

        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:enabled"])
      end
    rescue Organization::UnableToRemoveEnterpriseTeamMemberError, Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError => e
      failed_because_of_enterprise_team_member = true
    ensure
      if revert_because_failure
        with_write do
          organization.disable_two_factor_requirement(actor: actor) unless existing_required

          # reset disallowed methods if they could have been changed - clear and re-add each existing method disallowed
          existing_disallowed_methods.each do |method|
            organization.add_disallowed_two_factor_method(method: method, actor: actor, log_event: false)
          end
        end

        OrganizationMailer.failed_two_factor_enforcement(actor, organization, enterprise_team_member_removal_failure: failed_because_of_enterprise_team_member).deliver_now!
        GitHub.dogstats.increment("organization", tags: ["action:two_factor_requirement", "type:failed"])
      end
    end
  end

  def validate_actor!
    # Site admins may enable 2FA requirement on an org if there is at least
    # one org admin with 2FA enabled.
    return if actor.site_admin? && organization.can_two_factor_requirement_be_enabled? && @disallowed_methods.empty?

    unless organization.adminable_by?(actor) && (
      # Only check if actor is a User. When enabling 2FA on an organization
      # after being added to a business we pass the organization as the actor.
      !actor.user? || (actor.two_factor_authentication_enabled? &&
        !actor.has_any_given_2fa_methods_configured?(@disallowed_methods))
    )
      raise InvalidActor.new(actor)
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

  # restore commented collaborator lines after https://github.com/github/authorization/issues/4526
  def notify_users_requirement_and_methods_enforced
    # rubocop:disable Layout/CommentIndentation

    no_2fa_members = organization.members_with_two_factor_disabled
    no_2fa_billing = organization.billing_managers_with_two_factor_disabled
    # no_2fa_collaborators = organization.outside_collaborators_with_two_factor_disabled

    no_2fa_members.each do |user|
      OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "member of").deliver_later
    end

    no_2fa_billing.each do |user|
      OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "billing manager of").deliver_later
    end

    # no_2fa_collaborators.each do |user|
    #   OrganizationMailer.two_factor_enforcement_member_notification(user, organization, "collaborator within").deliver_later
    # end

    return if @disallowed_methods.empty?

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
