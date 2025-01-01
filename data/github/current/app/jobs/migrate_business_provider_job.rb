# typed: true
# frozen_string_literal: true

class MigrateBusinessProviderJob < ApplicationJob
  queue_as :migrate_business_provider

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "migrate-business-provider-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes

  retry_on_dirty_exit
  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    Failbot.report(error)
  end

  # this job is executed infrequently and its topic has been removed before due to a bug: https://github.com/github/external-identities/issues/3549
  # dry-run it periodically to prevent this from happening again
  schedule interval: 1.day, condition: -> { !GitHub.single_business_environment? }

  # Public: Migrate the business providers.  Currently only migrations from SAML to OIDC are supported.
  #
  # business_id - The ID of the Business to switch providers for
  # from_provider_id - The ID of the provider to switch from
  # to_provider_id - The ID of the provider to switch to
  #
  # Returns nothing
  def perform(business_id: nil, saml_provider_id: nil, oidc_provider_id: nil)
    if !business_id || !saml_provider_id || !oidc_provider_id
      GitHub.logger.info("Ran migrate_business_provider_job without arguments to prevent topic deletion")
      return
    end

    Failbot.push(business_id: business_id, saml_provider_id: saml_provider_id, oidc_provider_id: oidc_provider_id)

    business = if GitHub.flipper[:sorbet_find_issues_fix].enabled?
      Business.find_by(id: business_id)
    else
      Business.find(business_id)
    end
    return unless business && business.saml_provider && business.oidc_provider

    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "info.message" => "Starting migrate_business_provider_job",
      "gh.business.id" => business.id,
      "gh.business.slug" => business.slug,
    )

    if business.saml_provider.id == saml_provider_id && business.oidc_provider.id == oidc_provider_id
      lock!(business_id) do
        with_write { business.oidc_provider.migrate_from_saml! }
      end
    end

    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "info.message" => "Finished migrate_business_provider_job",
      "gh.business.id" => business.id,
      "gh.business.slug" => business.slug,
    )
  end

  private

  # Private: The restraint for locking and preventing simultaneous reconcile jobs
  # for the same external group team.
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  # Private: Use a GitHub::Restraint to prevent simultaneous updates
  def lock!(business_id)
    restraint_key = "#{LOCK_KEY}#{business_id}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
