# typed: true
# frozen_string_literal: true

class CheckOrgOwnedPrivateNetworksWithForksJob < ApplicationJob
  queue_as :check_org_owned_private_networks_with_forks
  retry_on_dirty_exit

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  MAX_NETWORKS = 100

  def perform
    check_for_desynced_networks(
      untracked_networks_query,
      "Found networks not tracked by org_owned_private_networks_with_forks table",
      "untracked"
    )
    check_for_desynced_networks(
      networks_which_should_not_be_tracked_query,
      "Found networks which should not be tracked by org_owned_private_networks_with_forks table",
      "should_not_be_tracked"
    )
  end

  def check_for_desynced_networks(query, log_message, tag)
    network_ids = GitHub.presto.run(query).second.flatten.uniq
    GitHub.dogstats.distribution("repos.oopnwf.desynced", network_ids.size, tags: ["type:#{tag}"])

    if network_ids.size > MAX_NETWORKS
      network_ids = network_ids.take(MAX_NETWORKS)
      GitHub.logger.info(
        log_message + " (truncated to #{MAX_NETWORKS} networks)",
        "code.namespace" => self.class.name,
        "gh.network.ids" => network_ids.to_s
      )
    else
      GitHub.logger.info(
        log_message,
        "code.namespace" => self.class.name,
        "gh.network.ids" => network_ids.to_s
      )
    end

    networks = RepositoryNetwork.where(id: network_ids)
    oopnwfs_by_network = OrgOwnedPrivateNetworkWithForks.where(network_id: network_ids).index_by(&:network_id)
    networks.each do |network|
      tracked_before_sync = oopnwfs_by_network[network.id] && oopnwfs_by_network[network.id].owner_id == network.root&.owner_id

      with_write { network.sync_org_owned_private_network_with_forks }

      oopnwf = OrgOwnedPrivateNetworkWithForks.find_by(network_id: network.id)
      tracked_after_sync = oopnwf && oopnwf.owner_id == network.root&.owner_id

      if tracked_before_sync != tracked_after_sync
        GitHub.dogstats.increment("repos.oopnwf.resynced", tags: ["type:#{tag}"])
        GitHub.logger.info(
          "Resynced networks which were #{tag.gsub("_", " ")} by org_owned_private_networks_with_forks table",
          "code.namespace" => self.class.name,
          "gh.network.id" => network.id
        )
      end
    end
  end

  def untracked_networks_query
    updated_at_limit = (RepositoryBulkPurgeJob::MINIMUM_AGE_TO_PURGE - 1.day).ago.to_date
    %Q(
      SELECT repo.source_id
      FROM hive.snapshots_presto.repositories AS repo
      WHERE repo.parent_id IS NULL
        AND (repo.active = TRUE
            OR repo.updated_at > TIMESTAMP '#{updated_at_limit}')
        AND repo.organization_id IS NOT NULL
        AND repo.public = FALSE
        AND
          (SELECT count(*)
          FROM hive.snapshots_presto.repositories AS fork
          WHERE parent_id IS NOT NULL
            AND repo.source_id = fork.source_id
            AND (fork.active = TRUE
                  OR fork.updated_at > TIMESTAMP '#{updated_at_limit}')) > 0
        AND source_id NOT IN
          (SELECT oopnwf.network_id
          FROM hive.snapshots_presto.org_owned_private_networks_with_forks AS oopnwf
          INNER JOIN hive.snapshots_presto.repositories AS repo ON repo.source_id = oopnwf.network_id
          AND repo.owner_id = oopnwf.owner_id)
    )
  end

  def networks_which_should_not_be_tracked_query
    updated_at_limit = 1.day.ago.beginning_of_day

    %Q(
      SELECT network_id
      FROM hive.snapshots_presto.org_owned_private_networks_with_forks
      WHERE updated_at < TIMESTAMP '#{updated_at_limit}'
        AND network_id NOT IN
          (SELECT oopnwf.network_id
          FROM hive.snapshots_presto.repositories AS repo
          INNER JOIN hive.snapshots_presto.org_owned_private_networks_with_forks AS oopnwf ON repo.source_id = oopnwf.network_id
          AND repo.owner_id = oopnwf.owner_id
          WHERE repo.parent_id IS NULL
            AND repo.organization_id IS NOT NULL
            AND repo.public = FALSE
            AND
              (SELECT count(*)
                FROM hive.snapshots_presto.repositories AS fork
                WHERE parent_id IS NOT NULL
                  AND repo.source_id = fork.source_id) > 0
            AND oopnwf.updated_at < TIMESTAMP '#{updated_at_limit}')
    )
  end
end
