# typed: true
# frozen_string_literal: true

module Issue::CloseIssueReferenceDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))
    has_many :close_issue_references
    destroy_dependents_in_background :close_issue_references
  end

  def update_close_issue_references
    UpdateCloseIssueReferencesJob.perform_later(id)
  end

  def async_closed_by_pull_requests_references_for(viewer:, include_closed_prs: true, order_by_state: true, unauthorized_organization_ids: [])
    async_close_issue_references.then do |references|
      pull_request_ids = references.pluck(:pull_request_id).compact
      Platform::Loaders::ActiveRecord.load_all(::PullRequest, pull_request_ids).then do |pulls|
        load_accessible_pulls = pulls.map do |pull|
          next unless pull
          Promise.all([pull.async_repository, pull.async_issue, pull.async_user]).then do |repo, _issue, _author|
            next if (pull.spammy? || repo.spammy?) && !viewer&.site_admin?

            repo.async_owner.then do |repo_owner|
              next if unauthorized_organization_ids.include?(repo_owner&.id)
              if repo.public?
                next pull if include_closed_prs
                next pull if pull.state != :closed
                nil
              else
                pull.async_readable_by?(viewer).then do |pull_readable|
                  next unless pull_readable

                  next pull if include_closed_prs
                  next pull if pull.state != :closed
                  nil
                end
              end
            end
          end
        end

        Promise.all(load_accessible_pulls).then do |accessible_pulls|
          accessible_pulls = order_by_state(accessible_pulls.compact) if order_by_state
          accessible_pulls.compact
        end
      end
    end
  end

  def cap_filtered_closed_by_pull_requests_references_for_with_limit(viewer:, user_linked_only: false, include_closed_prs: true, order_by_state: true, cap_filter:, limit:, batch_size:)
    filtered_pulls = T.let([], Array)
    close_issue_references.in_batches(of: batch_size) do |references|
      # this will be called multiple times with references being the current batch

      accessible_pulls = async_cap_filtered_closed_by_pull_requests_from_references(
        references: references,
        viewer: viewer,
        user_linked_only: user_linked_only,
        include_closed_prs: include_closed_prs,
        order_by_state: order_by_state,
        cap_filter: cap_filter).sync

      filtered_pulls = filtered_pulls.concat(accessible_pulls.compact)
      break if filtered_pulls.size >= limit
    end

    filtered_pulls = order_by_state(filtered_pulls.compact) if order_by_state
    filtered_pulls.compact.take(limit)
  end

  def async_cap_filtered_closed_by_pull_requests_references_for(viewer:, user_linked_only: false, include_closed_prs: true, order_by_state: true, cap_filter:)
    async_close_issue_references.then do |references|
      async_cap_filtered_closed_by_pull_requests_from_references(
        references: references,
        viewer: viewer,
        user_linked_only: user_linked_only,
        include_closed_prs: include_closed_prs,
        order_by_state: order_by_state,
        cap_filter: cap_filter)
    end
  end

  def async_cap_filtered_closed_by_pull_requests_from_references(references:, viewer:, user_linked_only: false, include_closed_prs: true, order_by_state: true, cap_filter:)
    # `manual` references are those that are linked to a pull request via the UI, not via markdown comment
    pull_request_ids = (user_linked_only ? references.select { |ref| ref.source == "manual" } : references)
                         .pluck(:pull_request_id)
                         .compact
    Platform::Loaders::ActiveRecord.load_all(::PullRequest, pull_request_ids).then do |pulls|
      pulls = pulls.compact
      Promise.all(pulls.map(&:async_repository)).then do |repos|
        repos = repos.map { |repo| repo if repo&.active? }.compact.index_by(&:id)
        pulls = pulls.select { |pull| repos.include?(pull.repository_id) }
        authorized_pulls = cap_filter.authorized_resources(pulls.compact)

        load_accessible_pulls = authorized_pulls.map do |pull|
          next if !pull
          Promise.all([pull.async_issue, pull.async_user]).then do |_issue, _user|
            repo = repos[pull.repository_id]
            next if (pull.spammy? || repo.spammy?) && !viewer&.site_admin?

            readable_promise = repo.public? ? Promise.resolve(true) : pull.async_readable_by?(viewer)
            readable_promise.then do |readable|
              next if !readable
              next pull if include_closed_prs
              next pull if pull.state != :closed
              nil
            end
          end
        end

        Promise.all(load_accessible_pulls).then do |accessible_pulls|
          accessible_pulls = order_by_state(accessible_pulls.compact) if order_by_state
          accessible_pulls.compact
        end
      end
    end
  end

  def closed_by_pull_requests_references_for(viewer:, unauthorized_organization_ids:, include_closed_prs: true, order_by_state: true)
    async_closed_by_pull_requests_references_for(
      viewer: viewer,
      include_closed_prs: include_closed_prs,
      order_by_state: order_by_state,
      unauthorized_organization_ids: unauthorized_organization_ids,
    ).sync
  end

  def cap_filtered_closed_by_pull_requests_references_for(viewer:, user_linked_only: false, include_closed_prs: true, order_by_state: true, cap_filter:, limit: nil, batch_size: 1000)
    if limit
      cap_filtered_closed_by_pull_requests_references_for_with_limit(
        viewer: viewer,
        user_linked_only: user_linked_only,
        include_closed_prs: include_closed_prs,
        order_by_state: order_by_state,
        cap_filter: cap_filter,
        limit: limit,
        batch_size: batch_size
      )
    else
      async_cap_filtered_closed_by_pull_requests_references_for(
        viewer: viewer,
        user_linked_only: user_linked_only,
        include_closed_prs: include_closed_prs,
        order_by_state: order_by_state,
        cap_filter: cap_filter
      ).sync
    end
  end

  # Total number of close_issue_references on this issue. Used for prefilling
  # data in the view.
  def close_issue_references_count
    @close_issue_references_count ||= CloseIssueReference
      .viewable_for(viewer: User.find_by(id: GitHub.context[:actor_id]), issue: self)
      .count
  end
  attr_writer :close_issue_references_count

  # Used to determine if a given pull_request_id might close an issue
  def may_be_closed_by?(pull_request_id)
    return false if pull_request?
    return false unless open?

    possible_closing_pull_request_ids.include?(pull_request_id)
  end

  private

  # Private
  #
  # Accepts an array of PullRequest objects
  # Returns object in order of merged, open, draft, and closed
  def order_by_state(pulls)
    prs_by_state = pulls.group_by(&:state)
    [
      prs_by_state[:merged],
      prs_by_state[:open]&.partition { |pr| !pr.draft },
      prs_by_state[:closed],
    ].flatten.compact
  end

  # Internal
  #
  # Returns pull_request_ids that might close the issue. NOTE: this method
  # does not check user permissions to access pull request, so this
  # should only be used after permissions have already been checked.
  #
  # Values are cached for use in the view, as many `cross_references` may be loaded
  # to determine whether the reference is also a closing reference.
  def possible_closing_pull_request_ids
    @possible_closing_pull_request_ids ||= pull_request? ? [] : close_issue_references.map(&:pull_request_id)
  end
end
