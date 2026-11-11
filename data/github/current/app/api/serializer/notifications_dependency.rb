# typed: true
# frozen_string_literal: true

module Api::Serializer::NotificationsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def repository_unread_count(repository_and_count, options = nil)
    repository, count = repository_and_count
    {
      repository: simple_repository_hash(repository, options),
      unread_count: count,
    }
  end

  def rollup_summaries_hashes(summaries, options = {})
    repo_ids = Set.new
    summaries.each do |hash|
      repo_ids << hash[:list][:id]
    end

    options[:repos] = rollup_summary_lookup(Repository, repo_ids, [:owner])

    summaries.map { |hash| rollup_summary_hash(hash, options) }.compact
  end

  # Translates a NotificationSummary Hash into a Hash to be serialized as JSON.
  #
  # summary - NotificationSummary Hash from Newsies::Web.all or
  #           NotificationSummary#to_summary_hash.
  # options - Optional Hash of lookup tables to help prepare summaries.
  #           :repos  - Hash of String ID => Hash of repositories referenced in
  #                     the Summary.
  #
  def rollup_summary_hash(summary, options = nil)
    repos_lookup = (options && options[:repos]) || {}
    return unless repo = repos_lookup[summary[:list][:id]]

    repo_serializer_options = options ? options.dup : {}
    repo_serializer_options.delete(:repos)

    summary_fields = [:id, :unread, :reason]
    hash = summary.slice(*summary_fields).update \
      updated_at: time(summary[:updated_at]),
      last_read_at: time(summary[:last_read_at]),
      subject: rollup_summary_thread_hash(summary, repo, options, current_user: options[:current_user]),
      repository: simple_repository_hash(repos_lookup[summary[:list][:id]], repo_serializer_options)

    rollup_summary_rels(summary, hash)
    hash[:reason] = "subscribed" if hash && hash[:reason].blank?
    repo_url = hash[:repository][:url]
    hash[:repository].update \
      notifications_url: repo_url + "/notifications{?since,all,participating}",
      subscription_url: repo_url + "/subscription"

    hash
  end

  def newsies_subscription_hash(subscription, options = {})
    if options[:list].blank? && options[:summary].blank?
      raise ArgumentError, "You must provide a :list or :summary as one of the options"
    end

    hash = {
      subscribed: subscription.subscribed?,
      ignored: subscription.ignored?,
      reason: subscription.reason,
      created_at: time(subscription.valid? ? subscription.created_at : nil),
    }

    if options[:summary]
      url = rollup_summary_url(options[:summary])
      hash.update \
        url: url + "/subscription",
        thread_url: url
    else
      repo_url = url("/repos/#{options[:list].name_with_owner_for_api(use: options[:serialize_login])}")
      hash.update \
        url: repo_url + "/subscription",
        repository_url: repo_url
    end

    hash
  end

  def rollup_summary_lookup(model, ids, includes = [])
    ids = ids.to_a
    records = model.where(id: ids).includes(includes).index_by(&:id)

    ids.inject({}) do |memo, id|
      if record = records[id.to_i]
        memo[id] = record
      end
      memo
    end
  end

  def rollup_summary_thread_hash(summary, repo, options = {}, current_user: nil)
    return {} unless thread = summary[:thread]

    view = ::Notifications::SummaryView.new(summary)
    latest = view.last_item

    h = {
      title: rollup_summary_title(thread, summary, current_user),
      url: rollup_summary_item_url(thread, summary, repo, options),
      latest_comment_url: rollup_summary_item_url(latest, summary, repo, options),
    }

    h[:type] = if summary[:is_pull_request]
      PullRequest.name
    else
      thread[:type].sub(/.*:/, "")
    end

    h
  end

  def rollup_summary_title(thread, summary, current_user)
    case thread[:type]
    when "RepositoryAdvisory"
      advisory = RepositoryAdvisory.find_by(ghsa_id: summary[:number])
      advisory&.get_title(current_user)
    else
      summary[:title]
    end
  end

  def rollup_summary_url(summary)
    url("/notifications/threads/#{summary[:id]}")
  end

  def rollup_summary_rels(summary, options)
    summary_url = rollup_summary_url(summary)
    options.update \
      url: summary_url,
      subscription_url: summary_url + "/subscription"
  end

  def rollup_summary_item_url(item, summary, repo, options = {})
    case item[:type]
    when Issue.name, IssueEventNotification.name
      summary[:is_pull_request] ? rollup_summary_pull_refs(summary, repo, options) : rollup_summary_issue_refs(summary, repo, options)
    when ::Commit.name, "Grit::Commit"
      rollup_summary_commit_refs(item, repo, options)
    when IssueComment.name
      rollup_summary_issue_comment_refs(item, repo, options)
    when PullRequestReviewComment.name
      rollup_summary_review_comment_refs(item, repo, options)
    when CommitComment.name
      rollup_summary_commit_comment_refs(item, repo, options)
    when Release.name
      rollup_summary_release_refs(item, repo, options)
    when RepositoryVulnerabilityAlert.name
      rollup_summary_repository_vulnerability_alert_refs(repo, options)
    when Discussion.name
      rollup_summary_discussion_refs(summary, repo, options)
    end
  end

  def rollup_summary_issue_comment_refs(item, repo, options = {})
    id = item[:id]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/issues/comments/#{id}")
  end

  def rollup_summary_review_comment_refs(item, repo, options = {})
    id = item[:id]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/pulls/comments/#{id}")
  end

  def rollup_summary_commit_comment_refs(item, repo, options = {})
    id = item[:id]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/comments/#{id}")
  end

  def rollup_summary_commit_refs(item, repo, options = {})
    sha = item[:id]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{sha}")
  end

  def rollup_summary_pull_refs(summary, repo, options = {})
    num = summary[:issue_number]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/pulls/#{num}")
  end

  def rollup_summary_issue_refs(summary, repo, options = {})
    num = summary[:issue_number]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/issues/#{num}")
  end

  def rollup_summary_release_refs(summary, repo, options = {})
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/releases/#{summary[:id]}")
  end

  def rollup_summary_repository_vulnerability_alert_refs(repo, options = {})
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}")
  end

  def rollup_summary_discussion_refs(item, repo, options = {})
    num = item[:number]
    url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/discussions/#{num}")
  end
end
