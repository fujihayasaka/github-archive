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

  def initialize(*arguments)
    @business = arguments[0]
    @actor = arguments[1]

    super(@business, @actor)
  end

  def perform(business, actor)
    raise ArgumentError, "business cannot be nil" if business.nil?
    raise ArgumentError, "actor cannot be nil" if actor.blank?

    @business = business
    @actor = actor
    @status = EnforceTwoFactorRequirementOnBusinessJob.status!(business)

    enforcement_failed = T.let(true, T::Boolean)

    status.track do
      validate_actor!
      validate_organizations!

      notify_members_organizations_removal
      notify_outside_collaborators_organizations_removal

      with_write do
        ApplicationRecord::Domain::Users.transaction do
          ApplicationRecord::Domain::ConfigurationEntries.transaction do
            business.enable_two_factor_required(actor: actor, force: true, log_event: true)

            # Remove non-two-factor affiliated users for each organization
            organization_jobs.each do |job|
              job.remove_affiliated_users_with_two_factor_disabled(send_notification: false)
            end

            remove_business_users_with_two_factor_disabled
          end
        end
      end
      enforcement_failed = false
    end

    GitHub.dogstats.increment("business", tags: ["action:two_factor_requirement", "type:enabled"])
  ensure
    if enforcement_failed
      BusinessMailer.failed_two_factor_enforcement(actor, business).deliver_later
      GitHub.dogstats.increment("business", tags: ["action:two_factor_requirement", "type:failed"])
    end
  end

  def organization_jobs
    business.organizations.map do |org|
      EnforceTwoFactorRequirementOnOrganizationJob.new(org, actor)
    end
  end

  def notify_members_organizations_removal
    no_2fa_users = business.organization_members.two_factor_disabled
    return if no_2fa_users.empty?

    business_abilities = business.business_org_abilities(actor_ids: no_2fa_users.map(&:id))
    business_organizations = Organization.where(id: business_abilities.map(&:subject_id)).index_by(&:id)

    user_organizations = business_abilities.each_with_object(Hash.new { |h, k| h[k] = [] }) do |ability, res|
      res[ability.actor_id] << business_organizations[ability.subject_id]
    end

    no_2fa_users.each do |user|
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
    no_2fa_collaborators = business.outside_collaborators_with_two_factor_disabled
    return if no_2fa_collaborators.empty?

    no_2fa_collaborators.each do |user|
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

  def validate_organizations!
    non_compliant_organizations = \
      business.organizations.reject(&:can_two_factor_requirement_be_enabled?).map(&:login)
    return unless non_compliant_organizations.any?

    raise OrganizationCannotEnforceTwoFactor.new(non_compliant_organizations)
  end

  def validate_actor!
    # Site admins may enable 2FA requirement on a business if there is at least
    # one business admin with 2FA enabled.
    return if actor.site_admin? && business.can_two_factor_requirement_be_enabled?

    # Business admins may enable 2FA if they have 2FA enabled
    return if business.adminable_by?(actor) && actor.two_factor_authentication_enabled?

    raise InvalidActor.new(actor)
  end

  def remove_business_users_with_two_factor_disabled
    return if business.members_without_2fa_allowed?
    remove_owners_with_two_factor_disabled
    remove_billing_managers_with_two_factor_disabled
  end

  def event_prefix
    business.event_prefix
  end

  def event_payload
    {
      actor: actor,
      actor_id: actor.id,
    }.merge(event_context)
  end

  private

  def model_instrumenter
    @model_instrumenter ||= Instrumentation::ModelInstrumenter.new(self)
  end

  def event_context(prefix: event_prefix)
    business.event_context(prefix: prefix)
  end

  def remove_owners_with_two_factor_disabled
    business.owners_with_two_factor_disabled.find_each do |user|
      business.remove_owner(
        user,
        actor: actor,
        reason: Business::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      )
      create_in_app_notification(user)
    end
  end

  def remove_billing_managers_with_two_factor_disabled
    business.billing_managers_with_two_factor_disabled.find_each do |user|
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
