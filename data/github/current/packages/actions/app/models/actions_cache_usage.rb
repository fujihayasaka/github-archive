# typed: true
# frozen_string_literal: true

class ActionsCacheUsage < ApplicationRecord::Domain::Billing
  self.table_name = "actions_cache_usages"
  belongs_to :repository

  def self.get_repo_cache_usage(repo_id)
    started_at = GitHub::Dogstats.monotonic_time
    self.where(repository_id: repo_id).first
  ensure
    GitHub.dogstats.distribution("actions_cache_usage.repo_usage_fetch.time", GitHub::Dogstats.duration(started_at), tags: ["action:actions_cache_usage.repo"])
  end

  def self.get_org_cache_usage(org_id, repo = nil)
    started_at = GitHub::Dogstats.monotonic_time
    if repo.nil?
      repo_ids = self.get_active_repo_ids(org_id)
    else
      repo = ActiveRecord::Base.sanitize_sql_like(repo.to_s.strip.downcase)
      repo_ids = self.get_active_repo_ids_by_repo_name(org_id, repo)
    end

    repo_ids = repo_ids.empty? ? nil : repo_ids
    self.select("coalesce(SUM(active_caches_size), 0) AS total_active_caches_size, coalesce(SUM(active_caches_count), 0) AS total_active_caches_count")
      .where(owner_id: org_id,
        active_caches_size: 1..,
        repository_id: repo_ids).first
  ensure
    GitHub.dogstats.distribution("actions_cache_usage.org_usage_fetch.time", GitHub::Dogstats.duration(started_at), tags: ["action:actions_cache_usage.org", "repo:#{repo}"])
  end

  def self.get_org_cache_usage_order_by_size_with_repo_details(org_id, page, per_page, sort = nil, repo = nil)
    started_at = GitHub::Dogstats.monotonic_time

    sort = sort.nil? ? "size-desc" : sort
    order = order_to_orderby_clause_map[sort]

    if repo.nil?
      repo_ids = self.get_active_repo_ids(org_id)
    else
      repo = ActiveRecord::Base.sanitize_sql_like(repo.to_s.strip.downcase)
      repo_ids = self.get_active_repo_ids_by_repo_name(org_id, repo)
    end

    repo_ids = repo_ids.empty? ? nil : repo_ids
    self.where(owner_id: org_id, active_caches_size: 1.., repository_id: repo_ids).order(order).paginate(page: page, per_page: per_page).preload(:repository)
  ensure
    GitHub.dogstats.distribution("actions_cache_usage.org_usage_fetch_by_repo_with_repo_details.time", GitHub::Dogstats.duration(started_at), tags: ["action:actions_cache_usage.org_by_repo_with_repo_details"])
  end

  def self.get_enterprise_cache_usage(current_enterprise)
    started_at = GitHub::Dogstats.monotonic_time
    org_ids = current_enterprise.organizations.pluck(:id)
    get_cache_usage_for_orgs(org_ids: org_ids, slice: 1000)
  ensure
    GitHub.dogstats.distribution("actions_cache_usage.enterprise_usage_fetch.time", GitHub::Dogstats.duration(started_at), tags: ["action:actions_cache_usage.enterprise"])
  end

  def self.get_cache_usage_for_orgs(org_ids: nil, slice: 1000)
    total_active_caches_size = 0
    total_active_caches_count = 0
    org_ids.each_slice(slice) do |org_slice|
      scope = self.select("SUM(active_caches_size) AS total_active_caches_size, SUM(active_caches_count) AS total_active_caches_count").where(owner_id: org_slice).first
      if !scope.total_active_caches_count.nil? && !scope.total_active_caches_size.nil?
        total_active_caches_size += scope.total_active_caches_size
        total_active_caches_count += scope.total_active_caches_count
      end
    end
    {
      total_active_caches_size: total_active_caches_size,
      total_active_caches_count: total_active_caches_count
    }
  end

  def self.order_to_orderby_clause_map
    {
      "size-asc" => "active_caches_size ASC",
      "size-desc" => "active_caches_size DESC",
    }
  end

  def self.get_active_repo_ids(org_id)
    Repository.where("organization_id = #{org_id} and owner_id = #{org_id} and repositories.active is not NULL").pluck(:id)
  end

  def self.get_active_repo_ids_by_repo_name(org_id, repo)
    Repository.where("organization_id = #{org_id} and owner_id = #{org_id} and repositories.active is not NULL and repositories.name like ?",  "%#{repo}%").limit(1000).pluck(:id)
  end

end
