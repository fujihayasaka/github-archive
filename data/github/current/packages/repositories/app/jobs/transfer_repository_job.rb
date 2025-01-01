# typed: true
# frozen_string_literal: true

class TransferRepositoryJob < ApplicationJob
  queue_as :transfer_repository

  retry_on StandardError
  discard_on Repository::TransferDependency::TransferFailedError do |_job, err|
    raise err
  end

  def perform(repository_id, actor_id, new_owner_id, team_ids = [], options = {})
    notify_target = options.with_indifferent_access[:notify_target] || false

    Failbot.push(
      "gh.job.name": self.class.name,
      "gh.actor.id": actor_id,
      "gh.repo.id": repository_id,
      "gh.repo.new_owner.id": new_owner_id,
      "gh.team.ids": team_ids.join(","),
    )

    repository = Repositories::Public.find_active!(repository_id)
    old_nwo = repository.name_with_display_owner
    old_owner = User.find(repository.owner_id)
    new_owner = User.find(new_owner_id)
    actor = User.find(actor_id)

    GitHub.stratocaster.disable do
      target_teams = new_owner.teams.where(id: team_ids)
      transfer_successful = throttle_on_abilities_cluster do
        with_write { repository.transfer_ownership_to(new_owner, actor: actor, target_teams: target_teams) }
      end

      if transfer_successful
        # fire repo added to installation webhook
        if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
          T.cast(Repositories.domain.reload(repository), Repository).instrument_repo_added_to_installations_across_all_repositories(actor: actor) # rubocop:todo GitHub/AvoidCast
        else
          repository.reload.instrument_repo_added_to_installations_across_all_repositories(actor: actor)
        end
        # safe to trigger an update to the search index now
        repository.instrument_search_transfer_ownership_to(old_owner)

        if notify_target
          AccountMailer.immediate_repository_transfer(repository, actor, new_owner, old_nwo).deliver_now
        end

        if GitHub.sponsors_enabled? && SponsorsListing.for_sponsorable_user_or_org([old_owner.id, new_owner.id]).any?
          UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: old_owner.id)
          UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: new_owner.id)
        end
      end
    end
  end

  # Transferring repos generates a lot of ability grants which can cause replication delay.
  # Ability::Grant throttles on Mysql1 so let's wait until that is in a good state before beginning the transfer.
  def throttle_on_abilities_cluster(&block)
    Ability.throttle(&block)
  end
end
