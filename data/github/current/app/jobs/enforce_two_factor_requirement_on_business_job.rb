# typed: true
# frozen_string_literal: true

# Run when a business admin enables the 2FA requirement on a business.
#
# Removes: - Business admins that do not have 2FA enabled.
#          - Business billing managers that do not have 2FA enabled.
#          - Organization members, outside collaborators, and billing managers
#            that do not have 2fa enabled.
class EnforceTwoFactorRequirementOnBusinessJob < ApplicationJob
  queue_as :enforce_two_factor_requirement

  attr_reader :actor, :business, :status

  class InvalidActor < StandardError; end
  class OrganizationCannotEnforceTwoFactor < StandardError; end

  before_enqueue do |job|
    # Create a JobStatus for the job being enqueued.
    business = job.arguments.first
    with_write { JobStatus.create(id: EnforceTwoFactorRequirementOnBusinessJob.job_id(business)) }
  end

  def self.job_id(business)
    "enforce-two-factor-requirement-on-business_#{business.id}"
  end

  def self.status(business)
    JobStatus.find(EnforceTwoFactorRequirementOnBusinessJob.job_id(business))
  end

  def self.status!(business)
    JobStatus.find!(EnforceTwoFactorRequirementOnBusinessJob.job_id(business))
  end

  def self.clear_status!(business)
    # clears the JobStatus in KV (development only).  this prevents caching issues when changing settings rapidly for
    # testing.
    return unless Rails.env.development?
    status(business)&.destroy
  end

  def initialize(*arguments, disallowed_methods: [])
    @business = arguments[0]
    @actor = arguments[1]
    @disallowed_methods = disallowed_methods

    super(@business, @actor, disallowed_methods: @disallowed_methods)
  end

  def perform(business, actor, disallowed_methods: [])
    raise ArgumentError, "business cannot be nil" if business.nil?
    raise ArgumentError, "actor cannot be nil" if actor.blank?

    @business = business
    @actor = actor
    @disallowed_methods = disallowed_methods
    @status = EnforceTwoFactorRequirementOnBusinessJob.status!(business)

    if Rails.env.development?
      # avoids race conditions between job enqueuing and the page load of settings/security
      sleep 1
    end

    enforcement_failed = T.let(true, T::Boolean)
    existing_disallowed_methods = business.get_two_factor_disallowed_methods!

    status.track do
      validate_actor!
      validate_organizations!

      if business.members_without_2fa_allowed?
        notify_users_requirement_and_methods_enforced
      else
        notify_members_organizations_removal
      end

      # move back into "else" after https://github.com/github/authorization/issues/4526
      notify_outside_collaborators_organizations_removal

      with_write do
        ApplicationRecord::Domain::Users.transaction do
          ApplicationRecord::Domain::ConfigurationEntries.transaction do
            business.enable_two_factor_required(actor: actor, force: true, log_event: true)

            if business.can_disallow_two_factor_methods?
              if @disallowed_methods.any?
                @disallowed_methods.each do |method|
                  business.add_disallowed_two_factor_method(method: method, actor: actor, force: true,
                    log_event: !business.insecure_two_factor_methods_disallowed?
                  )
                end
              else
                business.clear_disallowed_two_factor_methods(actor: actor,
                  log_event: business.insecure_two_factor_methods_disallowed?
                )
              end
            end

            # this is members_without_2fa_allowed aware - will remove OCs only if members_without_2fa_allowed
            # or will remove everyone if 2FA is hard-enforced
            # remove after https://github.com/github/authorization/issues/4526, since no users will need to be removed
            organization_jobs.each do |job|
              job.remove_affiliated_users_with_two_factor_noncompliance(send_notification: false)
            end

            # Remove non-two-factor affiliated users for each organization, members_without_2fa_allowed-aware
            remove_business_users_with_two_factor_noncompliance
          end
        end
      end
      enforcement_failed = false
    end

    GitHub.dogstats.increment("business", tags: ["action:two_factor_requirement", "type:enabled"])
  ensure
    if enforcement_failed
      with_write do
        business.disable_two_factor_requirement(actor: actor)

        # reset disallowed methods if they could have been changed - clear and re-add each existing method disallowed
        if business.can_disallow_two_factor_methods?
          existing_disallowed_methods.each do |method|
            business.add_disallowed_two_factor_method(method: method, actor: actor, force: true, log_event: false)
          end
        end
      end

      BusinessMailer.failed_two_factor_enforcement(actor, business).deliver_later
      GitHub.dogstats.increment("business", tags: ["action:two_factor_requirement", "type:failed"])
    end
  end

  def organization_jobs
    business.organizations.map do |org|
      EnforceTwoFactorRequirementOnOrganizationJob.new(org, actor, disallowed_methods: @disallowed_methods)
    end
  end

  def notify_members_organizations_removal
    removal_members = business.organization_members.two_factor_disabled +
      business.organization_members.two_factor_enabled.filter { |m| m.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    return if removal_members.empty?

    business_abilities = business.business_org_abilities(actor_ids: removal_members.map(&:id))
    business_organizations = Organization.where(id: business_abilities.map(&:subject_id)).index_by(&:id)

    user_organizations = business_abilities.each_with_object(Hash.new { |h, k| h[k] = [] }) do |ability, res|
      res[ability.actor_id] << business_organizations[ability.subject_id]
    end

    removal_members.each do |user|
      BusinessMailer.removed_member_from_organizations(
          user,
          business,
          user_organizations[user.id],
      ).deliver_later

      model_instrumenter.instrument :remove_member, user: user,
                                 actor: actor,
                                 business: business,
                                 reason: "two_factor_requirement_non_compliance"
    end
  end

  def notify_outside_collaborators_organizations_removal
    removal_collaborators = business.outside_collaborators_with_two_factor_disabled +
      business.outside_collaborators.two_factor_enabled.filter { |c| c.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    return if removal_collaborators.empty?

    removal_collaborators.each do |user|
      BusinessMailer.removed_outside_collaborator_from_organizations(
          user,
          business,
          user.outside_collaborator_repositories(business: business).map(&:name_with_owner),
      ).deliver_later

      model_instrumenter.instrument :remove_member, user: user,
                                 actor: actor,
                                 business: business,
                                 reason: "two_factor_requirement_non_compliance"
    end
  end

  # restore commented collaborator lines after https://github.com/github/authorization/issues/4526
  def notify_users_requirement_and_methods_enforced
    # rubocop:disable Layout/CommentIndentation

    no_2fa_members = business.members_with_two_factor_disabled
    # no_2fa_collaborators = business.outside_collaborators_with_two_factor_disabled

    no_2fa_members.each do |user|
      BusinessMailer.two_factor_enforcement_member_notification(user, business, "member of").deliver_later
    end

    # no_2fa_collaborators.each do |user|
    #   BusinessMailer.two_factor_enforcement_member_notification(user, business, "collaborator within").deliver_later
    # end

    return if @disallowed_methods.empty? || !business.can_disallow_two_factor_methods?
    return if GitHub.enterprise? # GHES does not support SMS (insecure method) so we don't need to send mailers for it

    disallowed_method_owners = business.owners_with_two_factor_enabled
      .filter { |o| o.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    disallowed_method_billing_managers = business.billing_managers_with_two_factor_enabled
      .filter { |b| b.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    disallowed_method_members = business.members_with_two_factor_enabled
      .filter { |m| m.has_any_given_2fa_methods_configured?(@disallowed_methods) }
      .filter { |m| !disallowed_method_owners.include?(m) } # avoid duplicate notifications to owners, who are also members
    # disallowed_method_collaborators = business.outside_collaborators.two_factor_enabled
    #  .filter { |c| c.has_any_given_2fa_methods_configured?(@disallowed_methods) }

    disallowed_method_owners.each do |user|
      BusinessMailer.insecure_two_factor_method_enforcement_member_notification(user, business, "an owner of").deliver_later
    end

    disallowed_method_billing_managers.each do |user|
      BusinessMailer.insecure_two_factor_method_enforcement_member_notification(user, business, "a billing manager of").deliver_later
    end

    disallowed_method_members.each do |user|
      BusinessMailer.insecure_two_factor_method_enforcement_member_notification(user, business, "a member of").deliver_later
    end

    # disallowed_method_collaborators.each do |user|
      # BusinessMailer.insecure_two_factor_method_enforcement_member_notification(user, business, "collaborator within").deliver_later
    # end

    # rubocop:enable Layout/CommentIndentation
  end

  def validate_organizations!
    non_compliant_organizations = \
      business.organizations.reject(&:can_two_factor_requirement_be_enabled?).map(&:login)

    if @disallowed_methods.any?
      non_compliant_organizations += business.organizations.reject(&:can_disallow_two_factor_methods?).map(&:login)
    end

    return unless non_compliant_organizations.any?

    raise OrganizationCannotEnforceTwoFactor.new(non_compliant_organizations)
  end

  def validate_actor!
    # Site admins may enable 2FA requirement on a business if there is at least
    # one business admin with 2FA enabled.
    return if actor.site_admin? && business.can_two_factor_requirement_be_enabled? &&
      (@disallowed_methods.empty? || business.can_disallow_two_factor_methods?)

    # Business admins may enforce 2FA if they are compliant with what they are enforcing
    # (Have 2FA enabled and do not have any disallowed methods configured)
    return if business.adminable_by?(actor) && actor.two_factor_authentication_enabled? &&
      !actor.has_any_given_2fa_methods_configured?(@disallowed_methods)

    raise InvalidActor.new(actor)
  end

  def remove_business_users_with_two_factor_noncompliance
    return if business.members_without_2fa_allowed?
    remove_owners_with_two_factor_noncompliance
    remove_billing_managers_with_two_factor_noncompliance
  end

  def event_prefix
    business.event_prefix
  end

  def event_payload
    {
      actor: actor,
      actor_id: actor.id,
    }.merge(job_event_context)
  end

  private

  def model_instrumenter
    @model_instrumenter ||= Instrumentation::ModelInstrumenter.new(self)
  end

  def job_event_context(prefix: event_prefix)
    business.event_context(prefix: prefix)
  end

  def remove_owners_with_two_factor_noncompliance
    business.owners_with_two_factor_disabled.find_each do |user|
      business.remove_owner(
        user,
        actor: actor,
        reason: Business::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end

    return if @disallowed_methods.empty?

    method_noncompliant_owners = business.owners.two_factor_enabled
    .filter { |owner| owner.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    .find_each do |user|
      business.remove_owner(
        user,
        actor: actor,
        reason: Business::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def remove_billing_managers_with_two_factor_noncompliance
    business.billing_managers_with_two_factor_disabled.find_each do |user|
      business.billing.remove_manager(
        user,
        actor: actor,
        reason: Business::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end

    return if @disallowed_methods.empty?

    method_noncompliant_managers = business.billing_managers.two_factor_enabled
    .filter { |owner| owner.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    .find_each do |user|
      business.billing.remove_manager(
        user,
        actor: actor,
        reason: Business::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def create_in_app_notification(user)
    Business::RemovedMemberNotification.new(business, user).add_two_factor_requirement_non_compliance
  end
end
