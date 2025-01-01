# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class ActionsCacheUsageHelper
  def self.get_all_actions_cache
    ActionsCacheUsage.all
  end

  sig { params(repo: Repository, active_caches_size: T.untyped, active_caches_count: T.untyped, owner_id: T.untyped, created_at: T.untyped, is_results_usage: T.untyped).returns(T.untyped) }
  def self.save_repo_cache_usage(repo, active_caches_size, active_caches_count, owner_id, created_at, is_results_usage)
    if repo.feature_enabled?(:use_merged_cache_usage)
      ac = ActionsCacheUsage.find_by(repository_id: repo.id, is_results_usage: is_results_usage)
    else
      ac = ActionsCacheUsage.find_by(repository_id: repo.id)
    end

    if ac.nil?
      ActiveRecord::Base.connected_to(role: :writing) do
        ActionsCacheUsage.create(
          repository_id: repo.id,
          owner_id: owner_id,
          active_caches_size: active_caches_size,
          active_caches_count: active_caches_count,
          created_at: created_at,
          updated_at: created_at,
          is_results_usage: is_results_usage
        )
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        ac.update!(active_caches_size: active_caches_size, active_caches_count: active_caches_count, owner_id: owner_id, updated_at: created_at, is_results_usage: is_results_usage)
      end
    end
    GitHub.dogstats.increment("actions_cache_usage.hydro_message.success", tags: ["action:persist_hydro_message", "source:#{is_results_usage ? "results" : "artifact_cache"}"])
  end

  def self.transfer_cache_owner(repository, new_owner)
    if repository&.feature_enabled?(:use_merged_cache_usage)
      cache_usage = ActionsCacheUsage.where(repository_id: repository.id)
      if cache_usage
        cache_usage.update_all(owner_id: new_owner.id)
      end
    else
      cache_usage = ActionsCacheUsage.find_by(repository_id: repository.id)
      if cache_usage
        cache_usage.update(owner_id: new_owner.id)
      end
    end
  ensure
    GitHub.dogstats.increment("actions_cache_usage_helper.transfer_cache_owner", tags: ["action:transfer_cache_owner"])
  end

  def self.get_org_cache_usage_with_repo_details(org_id, page, per_page, sort, repo = nil)
    cache_usage_by_repo = ActionsCacheUsage.get_org_cache_usage_order_by_size_with_repo_details(org_id, page, per_page, sort, repo)
  ensure
    GitHub.dogstats.increment("actions_cache_usage_helper.get_org_cache_usage_with_repo_details", tags: ["action:get_org_cache_usage_with_repo_details"])
  end

  def self.get_org_cache_usage(org_id, repo = nil)
    cache_usage = ActionsCacheUsage.get_org_cache_usage(org_id, repo)
  ensure
    GitHub.dogstats.increment("actions_cache_usage_helper.get_org_cache_usage", tags: ["action:get_org_cache_usage", "repo:#{repo}"])
  end
end
