# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job only runs on Enterprise Server and should only be enqueued after a
# configuration run happens on an installation.
#
# This job ensures that in case the authentication mode for the Enterprise
# Server installation has changed to one that does not support 2FA
# (currently SAML and CAS), which is determined by
# GitHub.auth.two_factor_org_requirement_allowed?, the global business and any
# organizations with 2FA enforced get the 2FA requirement disabled.
class DisableTwoFactorRequirementJob < ApplicationJob
  queue_as :disable_two_factor_requirement

  RETRYABLE_ERRORS = [
    ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::QueryCanceled,
  ].freeze

  RETRYABLE_ERRORS.each do |error|
    retry_on(error) do |_job, error|
      Failbot.report(error)
    end
  end

  def perform
    return unless GitHub.enterprise?
    return if GitHub.auth.two_factor_org_requirement_allowed?

    if GitHub.global_business.two_factor_requirement_enabled?
      with_write do
        GitHub.global_business.disable_two_factor_required \
        log_event: true, actor: User.ghost
      end
    end

    orgs_with_two_factor_requirement.find_each do |org|
      with_write { org.disable_two_factor_requirement log_event: true, actor: User.ghost }
    end
  rescue NameError => e
    Failbot.report(e)
  end

  def orgs_with_two_factor_requirement
    organization_ids = Configuration::Entry.targeting_users
      .named(Configurable::TwoFactorRequired::KEY)
      .with_true_value
      .pluck(:target_id)
    Organization.where(id: organization_ids)
  end
end
