# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DestroyExternalProviderDependentsJob < ApplicationJob
  queue_as :destroy_external_provider_dependents

  MAX_CONCURRENT_JOBS = 1
  RESTRAINT_LOCK_TTL = 5.minutes
  LOCK_KEY = "destroy-external-provider-dependents-job:"

  MAX_RETRY_ATTEMPTS = 3
  RETRY_DELAY = 5.minutes
  ENQUEUE_INTERVAL = 30

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: RETRY_DELAY, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    Failbot.report(error)
  end
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
    Failbot.report(error)
  end

  resolve_tenant_context do |args|
    Business.find_by(id: args[:business_id])
  end

  # Public: Since removal of an external provider can take a long time, we want to
  #   add ability to notify the user when the removal is complete.  In order to do this,
  #   we need to know when the external groups and identities have been removed and teams cleaned up.
  #   This job is responsible for removing the external groups and identities and cleaning up the teams.
  #
  # provider_id - The ID of the provider that is being removed.
  # provider_type - The type of the provider that is being removed: Business::SamlProvider or Business::OIDCProvider
  # business_id - The ID of the business that the provider is linked to.
  # caller - Determines where the job is triggered from. Used for logging purposes only where parameters are recorded.
  #
  # Returns nothing
  def perform(provider_id:, provider_type:, business_id:, caller:)
    Failbot.push(provider_id: provider_id, provider_type: provider_type, business_id: business_id)

    unless provider_id && provider_type && business_id
      GitHub.dogstats.increment("external_identities.destroy_external_provider_dependents_job.no_provider_id_provider_type_business_id")
      return
    end

    business = Business.find_by(id: business_id)

    GitHub.logger.info(
      "info.message" => "Starting destroy_external_provider_dependents job",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_provider.id" => provider_id,
      "gh.external_provider.type" => provider_type,
      "gh.business.id" => business&.id,
      "gh.business.slug" => business&.slug,
      "gh.caller" => caller
    )

    begin
      return unless business

      lock!(provider_id, provider_type) do
        with_write do
          business.destroy_external_provider_dependents(provider_id, provider_type)
        end
      end
    ensure
      GitHub.logger.info(
        "info.message" => "Finished destroy_external_provider_dependents job",
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.external_provider.id" => provider_id,
        "gh.external_provider.type" => provider_type,
        "gh.business.id" => business&.id,
        "gh.business.slug" => business&.slug,
        "gh.caller" => caller
      )
    end
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
  def lock!(provider_id, provider_type)
    restraint_key = "#{LOCK_KEY}#{provider_id}-#{provider_type}"
    restraint.lock!(restraint_key, MAX_CONCURRENT_JOBS, RESTRAINT_LOCK_TTL) do
      yield
    end
  end
end
