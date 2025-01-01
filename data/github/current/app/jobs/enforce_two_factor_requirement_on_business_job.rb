# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Run when a business admin enables the 2FA requirement on a business.
#
# Removes outside collaborators that do not have 2fa enabled.
class EnforceTwoFactorRequirementOnBusinessJob < ApplicationJob
  queue_as :enforce_two_factor_requirement
  retry_on_dirty_exit

  attr_reader :actor, :business, :status

  class InvalidActor < StandardError; end
  class OrganizationCannotEnforceTwoFactor < StandardError; end

  before_enqueue do |job|
    # Create a EnterpriseAccounts::JobStatus for the job being enqueued.
    business = job.arguments.first
    with_write { EnterpriseAccounts::JobStatus.create(id: EnforceTwoFactorRequirementOnBusinessJob.job_id(business)) }
  end

  def self.prefix
    "enforce_two_factor_requirement_on_business"
  end

  resolve_tenant_context do |business|
    business
  end

  def self.job_id(business)
    "#{prefix}_#{business.id}"
  end

  def self.status(business)
    EnterpriseAccounts::JobStatus.find(EnforceTwoFactorRequirementOnBusinessJob.job_id(business))
  end

  def self.status!(business)
    EnterpriseAccounts::JobStatus.find!(EnforceTwoFactorRequirementOnBusinessJob.job_id(business))
  end

  def self.clear_status!(business)
    # clears the EnterpriseAccounts::JobStatus in KV (development only).  this prevents caching issues when changing settings rapidly for
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
    # check if methods is actually accidentally just a symbol, if so, change it to an array
    @disallowed_methods = [@disallowed_methods] if @disallowed_methods.is_a?(Symbol)
    @status = EnforceTwoFactorRequirementOnBusinessJob.status!(business)

    if Rails.env.development?
      # avoids race conditions between job enqueuing and the page load of settings/security
      sleep 1
    end

    enforcement_failed = T.let(true, T::Boolean)
    existing_required = business.two_factor_requirement_enabled?
    existing_disallowed_methods = business.get_two_factor_disallowed_methods!

    status.track do
      validate_actor!

      notify_users_requirement_and_methods_enforced

      # move back into "else" after https://github.com/github/authorization/issues/4526
      notify_outside_collaborators_organizations_removal

      with_write do
        ApplicationRecord::Domain::Users.transaction do
          ApplicationRecord::Domain::ConfigurationEntries.transaction do
            business.enable_two_factor_required(actor: actor, force: true, log_event: true)

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

            # will remove OCs only, remove after https://github.com/github/authorization/issues/4526, since no users will need to be removed
            organization_jobs.each do |job|
              job.remove_outside_collaborators_with_two_factor_noncompliance(send_notification: false)
            end
          end
        end
      end
      enforcement_failed = false
    end

    GitHub.dogstats.increment("business", tags: ["action:two_factor_requirement", "type:enabled"])
  ensure
    if enforcement_failed
      with_write do
        business.disable_two_factor_requirement(actor: actor) unless existing_required

        # reset disallowed methods if they could have been changed - clear and re-add each existing method disallowed
        existing_disallowed_methods.each do |method|
          business.add_disallowed_two_factor_method(method: method, actor: actor, force: true, log_event: false)
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

  def notify_outside_collaborators_organizations_removal
    removal_collaborators = business.outside_collaborators_with_two_factor_disabled +
      business.outside_collaborators.two_factor_enabled.filter { |c| c.has_any_given_2fa_methods_configured?(@disallowed_methods) }
    return if removal_collaborators.empty?

    removal_collaborators.each do |user|
      BusinessMailer.removed_outside_collaborator_from_organizations(
          user,
          business,
          @disallowed_methods.to_a,
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

    return if @disallowed_methods.empty?
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

  def validate_actor!
    # Site admins may enable 2FA requirement on a business if there is at least
    # one business admin with 2FA enabled.
    return if actor.site_admin? && business.can_two_factor_requirement_be_enabled? && @disallowed_methods.empty?

    # Business admins may enforce 2FA if they are compliant with what they are enforcing
    # (Have 2FA enabled and do not have any disallowed methods configured)
    return if business.adminable_by?(actor) && actor.two_factor_authentication_enabled? &&
      !actor.has_any_given_2fa_methods_configured?(@disallowed_methods)

    raise InvalidActor.new(actor)
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
end
