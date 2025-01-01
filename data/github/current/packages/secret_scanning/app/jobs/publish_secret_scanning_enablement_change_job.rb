# typed: true
# frozen_string_literal: true

# Publishes an enablement change notification for every repo in an org, or every repo in a business when secret
# scanning enablement changes
class PublishSecretScanningEnablementChangeJob < ApplicationJob
  queue_as :publish_secret_scanning_enablement_change
  retry_on_dirty_exit

  LONG_RUNNING_SEQUENCE_HOURS = 1

  # Publishes enablement change events for all repos in an organization, or for all repos in all organizations in a
  # business
  #
  # enablement_level               - Symbol that represents whether enablement is happening at the business or org lelve
  #                                  can be either: :business, :organization
  # actor_id                       - Id of the actor that initiated the job
  # business                       - Nilable Business to to publish events for
  # organization                   - Nilable Organization to publish events for
  sig { params(enablement_level: Symbol, actor_id: Integer, business: T.nilable(Business), organization: T.nilable(Organization)).void }
  def perform(enablement_level:, actor_id:, business:, organization:)
    GitHub::Logger.log_context(
      {
        actor_id: actor_id,
        method: "PublishSecretScanningEnablementChangeJob.perform",
        business_id: business&.id,
        orgnaization_id: organization&.id,
        enablement_level: enablement_level.to_s
      }
    ) do
      GitHub::Logger.log({ at: "start" })

      if enablement_level == :organization
        T.must(organization).repositories.each do |repo|
          # temporary - change the validity check setting of each repo
          repo_validity_checks = SecretScanning::Features::Repo::ValidityChecks.new(repo)
          org_validity_checks = SecretScanning::Features::Org::ValidityChecks.new(T.must(organization))
          if org_validity_checks.enabled? && repo_validity_checks.enable_with_org_or_enterprise?
            with_write { repo_validity_checks.enable(actor: User.find(actor_id)) }
          end

          # publish the event
          SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repo)
        end
        GitHub::Logger.log({ at: "finish" })
        return true
      end

      T.must(business).organizations.each do |org|
        # temporary - change the validity check setting of each org and repo
        business_validity_checks = SecretScanning::Features::Business::ValidityChecks.new(T.must(business))
        org_validity_checks = SecretScanning::Features::Org::ValidityChecks.new(T.must(org))
        if business_validity_checks.enabled? && org_validity_checks.enable_with_org_or_enterprise?
          with_write { org_validity_checks.enable(actor: User.find(actor_id)) }
        end

        # iterate each repo in the org
        org.repositories.each do |repo|
          # temporary - change the validity check setting of each org and repo
          repo_validity_checks = SecretScanning::Features::Repo::ValidityChecks.new(repo)
          if business_validity_checks.enabled? && repo_validity_checks.enable_with_org_or_enterprise?
            with_write { repo_validity_checks.enable(actor: User.find(actor_id)) }
          end

          #publish the event
          SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repo)
        end
      end

      feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(T.must(business))
      if feature.feature_available_for_user_repositories?
        offset_id = T.let(0, Integer)
        while batch = feature.list_enterprise_users_offset(offset_id: offset_id, per_page: 1000) do
          break if batch.empty?
          batch.each do |emu|
            emu.repositories.each do |repo|
              SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repo)
            end
          end
          offset_id = T.let(batch.last.id, Integer)
        end
      end

      GitHub::Logger.log({ at: "finish" })
      return true
    end
    true
  end
end
