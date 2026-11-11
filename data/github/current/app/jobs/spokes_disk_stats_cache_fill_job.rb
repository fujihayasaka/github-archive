# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Cache DFS disk stats.
# This is used by dgit's `pick_hosts`, which happens for all new
# repositories. Loading disk stats from the fileservers adds ~700ms
# to new repo and gist creation times.
class SpokesDiskStatsCacheFillJob < ApplicationJob
  queue_as :dgit_disk_stats

  def perform(queued_at)
    Failbot.push app: "github-dgit-debug"
    return if FeatureFlag.vexi.enabled_or_raise?(:dgit_disk_stats_fill_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    now = Time.now.to_i
    stale = now - GitHub.dgit_disk_stats_cache_ttl
    if queued_at > stale
      GitHub::DGit.fill_disk_stats_cache
    end
  end
end
