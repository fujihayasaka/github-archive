# typed: true
# frozen_string_literal: true

# Note: this is exploratory code for navbar counter caching invalidation. It is not yet ready for broad production use.
# Don't copy/paste this code or use it in production otherwise. See https://github.com/github/data-model/issues/1 for details.

class RedisCacheInvalidator
  def self.invalidate_pull_request_count_caches(repo_id, event)
    repo_actor = "Repository:#{repo_id}"

    if FeatureFlag.vexi.enabled?("navbar_counter_caching_pull_requests_count_invalidation", repo_actor, default: false)
      PullRequests::Cache::OpenPullRequestCountClient.new(Repository.new(id: repo_id), nil).invalidate(event)
    end

    if FeatureFlag.vexi.enabled?("open_issue_and_pr_count_caching_invalidation", repo_actor, default: false)
      Issues::Cache::OpenIssueAndPullRequestCountClient.new([repo_id]).invalidate(event)
    end
  end

  def self.invalidate_issue_count_caches(repo_id, event)
    repo_actor = "Repository:#{repo_id}"

    Issues::Cache::OpenIssueCountClient.new(Repository.new(id: repo_id), nil).invalidate(event)

    if FeatureFlag.vexi.enabled?("open_issue_and_pr_count_caching_invalidation", repo_actor, default: false)
      Issues::Cache::OpenIssueAndPullRequestCountClient.new([repo_id]).invalidate(event)
    end
  end
end

GitHub.subscribe(/\Aissue\.(create|destroy|transform_to_pull)\Z/) do |event, _, _, _, payload|
  repo_id = payload[:repo_id]
  next unless repo_id
  next if payload[:pull_request_id]

  RedisCacheInvalidator.invalidate_issue_count_caches(repo_id, event)
end

GitHub.subscribe("pull_request.create") do |event, _, _, _, payload|
  repo_id = payload[:repo_id]
  next unless repo_id
  next unless payload[:pull_request_id]

  RedisCacheInvalidator.invalidate_pull_request_count_caches(repo_id, event)
end

GitHub.subscribe(/\Aissue\.event\.(closed|reopened|converted_to_discussion)\Z/) do |event, _, _, _, payload|
  repo_id = payload[:repository_id]
  next unless repo_id
  repo_actor = "Repository:#{repo_id}"

  if payload[:pull_request_id]
    RedisCacheInvalidator.invalidate_pull_request_count_caches(repo_id, event)
  else
    RedisCacheInvalidator.invalidate_issue_count_caches(repo_id, event)
  end
end
