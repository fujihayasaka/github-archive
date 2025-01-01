# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class NppEnablementAndBackfillForGrcRepos < Base
      include GitHub::Memoizer

      CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"

      class RepositorySecurityConfiguration < ApplicationRecord::Notify
        self.table_name = :repository_security_configurations
      end

      class SecretScanningRepos < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :secret_scanning_repos
      end

      sig { returns(User) }
      memoize def ghost
        User.ghost
      end

      sig { override.void }
      def perform
        backfill_repos
      end

      sig { void }
      def backfill_repos
        orgs_to_repos = T.let({}, T::Hash[T.nilable(User), T::Array[Repository]])

        grc = SecurityConfiguration.where(target_type: "global").first!
        repository_security_configurations = RepositorySecurityConfiguration.where(
          security_configuration_id: grc.id,
          state: [1, 5]
        )

        repository_security_configurations.group_by(&:organization_id).each do |org_id, repos|
          owner = Organization.find_by(id: org_id)
          repos_to_enable_npp = SecretScanningRepos.where(id: repos.pluck(:repository_id), lower_confidence_patterns_enabled: 0, ghas_secret_scanning_enabled: 1, scannable: 1).pluck(:id)

          orgs_to_repos[owner] ||= []
          orgs_to_repos[owner] = T.must(orgs_to_repos[owner]) + Repository.where(id: repos_to_enable_npp).to_a
        end
        if dry_run?
          log "Would have triggered enablement update event for #{orgs_to_repos.keys.length} organizations and #{orgs_to_repos.values.flatten.length} repositories"
        else
          orgs_to_repos.each do |owner, repos|
            repos.each do |repo|
              if !repo.nil?
                payload = { actor: ghost, repo: repo, org: repo.organization }
                GitHub.instrument("repository_secret_scanning_non_provider_patterns.enabled", payload)
                SecretScanning::Instrumentation::EnablementChangePublisher.publish_enablement_change_event_for_repository(repo: repo)
              end
            end

            if owner.nil?
              repos.each do |repo|
                log "Owner is nil, triggering individual backfill for repo: " + repo.id.to_s
                GlobalInstrumenter.instrument("secret_scanning.low_confidence_backfill.repo", {
                  repository: repo,
                  actor: ghost,
                  owner: repo.owner,
                  feature_flags: repo.secret_scanning_post_receive_repo_flags,
                  type: :START,
                  requested_at: Time.now.utc,
                  business: {
                    id: repo.owner&.business&.id,
                    name: repo.owner&.business&.name,
                  },
                })
              end
            else
              repos.map(&:id).each_slice(100000) do |ids|
                GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
                  action: :START,
                  owner: owner,
                  requested_at: Time.current.utc,
                  type: :LOW_CONFIDENCE_PATTERN,
                  repository_ids: ids,
                  feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags
                })
                log "Triggered backfill for owner: #{owner.login} with #{ids.length} repositories"
              end
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::NppEnablementAndBackfillForGrcRepos.new(args).run
end
