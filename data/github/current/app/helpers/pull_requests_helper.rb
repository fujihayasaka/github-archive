# typed: true
# frozen_string_literal: true

module PullRequestsHelper
  include RepositoriesHelper
  include PullRequests::PageTitleHelper
  include ActionView::Helpers::UrlHelper
  include UrlHelper

  # Arbitrary hard limit on the potential number of destination repositories for
  # a pull request. This is a temporary fix to prevent slow page loads and
  # unicorns when the list of available forks is massive.
  MAX_DESTINATION_REPOS = 500

  def pull_request_page_info(pull)
    title = pull_request_page_title(pull)
    description = pull.repository.feature_enabled?(:new_pr_page_description) ? page_description(pull) : pull.body_text

    T.unsafe(self).page_info(
      title:         title,
      selected_link: :repo_pulls,
      stafftools:    UrlHelpers.stafftools_repository_pull_request_path(
                       pull.repository.owner_display_login, pull.repository.name, pull.number),
      description:   description,
      container_xl: true,
      richweb: {
        title:       title,
        url:         pull.url.to_s,
        description: description,
        card:        repository_twitter_image_card(pull.repository),
        image:       pull.repository.show_enhanced_og_image? ? pull.og_image_url : pull.repository.open_graph_image_url(T.unsafe(self).current_user),
        author:      pull.user&.display_login,
      },
      dashboard_pinnable_item_id: pull.id,
    )
  end

  def page_description(pull_request)
    viewer = T.unsafe(self).current_user
    cap_filter = T.unsafe(self).cap_filter

    truncate_text(pull_request.body_text(context: pull_request.body_html_context(viewer:, cap_filter:)) || "")
  end

  # Build a ranked list of repositories that are potential destinations for the
  # current comparison's pull request. The list is orded by the likeliness that
  # the destination repository is the correct place to send the pull request.
  #
  # The list includes the following repositories when applicable in the order
  # specified:
  #
  #   1. The base repository of the comparison.
  #   2. Each parent of the current repository up to the source repository.
  #   3. The current repository.
  #   4. All remaining repositories in the network sorted by name.
  #
  # Care is taken to ensure that the same repository does not appear more than
  # once in the list and that the current user has access to all repositories.
  def pull_request_destination_repositories(comparison)
    current_repository = T.unsafe(self).current_repository
    current_user = T.unsafe(self).current_user
    timer = Timer.start

    repos = []

    repos << comparison.base_repo if comparison.cross_repository?

    child, parent = current_repository, current_repository.parent
    while parent
      if !repos.include?(parent) && child.can_compare_against_parent?(current_user)
        repos << parent
      end
      child, parent = parent, parent.parent
    end

    repos << current_repository

    if T.unsafe(self).logged_in?
      repo_ids = current_user.associated_repository_ids(repository_ids: Repository.in_same_network_as(current_repository).ids)
      repos.concat Repository.where(id: repo_ids.first(MAX_DESTINATION_REPOS - repos.size)).with_owner.preload(:owner).to_a
    end
    repos.compact!

    repo = current_repository
    query = Arel.sql(<<-SQL, repository_id: repo.source_id, visibility: repo.public)
      SELECT id FROM repositories
      WHERE source_id = :repository_id AND public = :visibility AND active = 1
      ORDER BY watcher_count+0 DESC
      LIMIT 200
    SQL

    network_repo_ids = Repository.connection.select_values(query)

    if current_repository.private?
      associated_network_repository_ids = current_user.associated_repository_ids(repository_ids: network_repo_ids)
      network_repo_ids &= (associated_network_repository_ids + current_user.internal_repo_ids)
    end

    if network_repo_ids.any? && repos.size < MAX_DESTINATION_REPOS
      network_repos = Repository.with_owner.preload(:owner).where(id: network_repo_ids.first(MAX_DESTINATION_REPOS - repos.size))
      repos.concat network_repos.sort_by(&:name_with_owner)
    end

    repos = repos.uniq.reject { |repo| repo.owner.nil? }
    repos = repos.first(MAX_DESTINATION_REPOS)

    timer.stop
    GitHub.dogstats.distribution("pull_requests.compare_destination_repositories.time", timer.elapsed_ms,
                                 tags: ["action:#{T.unsafe(self).params[:action]}"])

    repos
  end

  def available_repositories_for(comparison, type)
    if comparison.repo.advisory_workspace?
      type == :base ? [comparison.base_repo] : [comparison.head_repo]
    else
      pull_request_destination_repositories(comparison)
    end
  end

  def merge_status_summary(context_states)
    downcased_states = context_states.map { |state| state && state.downcase }
    if downcased_states.length == 1
      if StatusCheckConfig::SUCCESS_STATES.include?(downcased_states.first)
        "1 check passed"
      elsif downcased_states.first == StatusCheckConfig::WAITING
        "1 check was waiting"
      elsif StatusCheckConfig::PENDING_STATES.include?(downcased_states.first)
        "1 check was pending"
      else
        "1 check failed"
      end
    elsif downcased_states.all? { |state| StatusCheckConfig::SUCCESS_STATES.include?(state) }
      "#{downcased_states.count} checks passed"
    else
      successful_count = downcased_states.count { |state| StatusCheckConfig::SUCCESS_STATES.include?(state) }
      "#{successful_count} of #{downcased_states.count} checks passed"
    end
  end

  def branch_label(repository, branch, prepend_login: false, prepend_repo_name: false, expandable: false, extra_classes: "", extra_link_classes: "", link: false, copy_button: false, repository_owner: nil)
    options = { class: "css-truncate-target" }

    content = if repository
      owner_login = repository.owner_display_login
      title = "#{owner_login}/#{repository.name}:#{branch}".scrub
      ref = content_tag(:span, branch.scrub, options)
      label = ref
      clipboard_contents = branch.scrub

      if prepend_repo_name
        repo = content_tag(:span, repository.name, options)
        clipboard_contents = [repository.name, clipboard_contents].join(":")
        label = safe_join([repo, ref], ":")
      end

      if prepend_login
        options[:class] += " user" unless link
        user = content_tag(:span, owner_login, options)
        if prepend_repo_name
          clipboard_contents = [owner_login, clipboard_contents].join("/")
          label = safe_join([user, label], "/")
        else
          clipboard_contents = [owner_login, branch].join(":")
          label = safe_join([user, ref], ":")
        end
      end

      label
    elsif repository_owner
      owner_login = repository_owner.display_login
      title = "This repository has been deleted"
      ref = content_tag(:span, branch.scrub, options)
      label = ref
      clipboard_contents = branch.scrub

      if prepend_login
        options[:class] += " user" unless link
        user = content_tag(:span, owner_login, options)
        clipboard_contents = [owner_login, branch].join(":")
        label = safe_join([user, ref], ":")
      end

      label
    else
      text = "unknown repository"
      content_tag(:span, text, options)
    end

    return_content = if expandable
      if link && repository
        content_tag(:span, title: title.try { |t| t.dup.force_encoding("utf-8").scrub! }, class: "commit-ref css-truncate user-select-contain expandable #{extra_classes}") do
          link_to(
            content.try { |c| c.force_encoding("utf-8") },
            repository_tree_path_root(repository, branch, :tree),
            title: title.try { |t| t.dup.force_encoding("utf-8") },
            class: "no-underline #{extra_link_classes}",
          )
        end
      else
        content_tag(:span,
                    content.try { |c| c.force_encoding("utf-8") },
                    title: title.try { |t| t.dup.force_encoding("utf-8") },
                    class: "commit-ref css-truncate user-select-contain expandable #{extra_classes}")
      end
    else
      content_tag(:span,
                  content.try { |c| c.force_encoding("utf-8") },
                  title: title.try { |t| t.dup.force_encoding("utf-8") },
                  class: extra_classes,
                  )
    end

    return_content += content_tag(:span) do
      if copy_button && clipboard_contents
        T.unsafe(ApplicationController).new.view_context.capture do
          T.unsafe(self).render Primer::Beta::ClipboardCopy.new(
            color: :muted,
            classes: "Link--onHover js-copy-branch",
            value: clipboard_contents.try { |c| c.force_encoding("utf-8").scrub! },
            "aria-label": "Copy",
            "data-copy-feedback": "Copied!",
            display: :inline_block,
            ml: 1
          )
        end
      end
    end

    return_content
  end

  def pull_branch_label(pull, base_or_head, expandable: false, extra_classes: "", link: false, copy_button: false)
    unless [:base, :head].include?(base_or_head)
      raise ArgumentError, "base_or_head must be either :base or :head"
    end

    repository    = pull.send("#{base_or_head}_repository")
    branch        = pull.send("display_#{base_or_head}_ref_name")
    prepend_login = pull.cross_repo?
    repository_owner = pull.send("#{base_or_head}_user") unless repository

    classes = "#{extra_classes} #{base_or_head == :base ? "base-ref" : "head-ref"}".squish
    branch_label(repository, branch, prepend_login: prepend_login, prepend_repo_name: pull.in_advisory_workspace?, expandable: expandable, extra_classes: classes, link: link, copy_button: copy_button, repository_owner: repository_owner)
  end

  def pull_request_commit_path(pull, commit)
    unless pull.is_a?(PullRequest)
      raise TypeError, "expected pull to be a PullRequest, but was #{pull.class}"
    end

    unless commit.is_a?(Commit)
      raise TypeError, "expected commit to be a Commit, but was #{commit.class}"
    end

    base_path = pull_request_path(pull)
    "#{base_path}/commits/#{commit.oid}"
  end

  # Public: Generate url for PR history state.
  #
  # pull_comparison - A PullRequest::Comparison.
  # anchor - Optional String URL anchor (default: nil)
  #
  # Returns String URL path.
  def pull_request_comparison_path(pull_comparison, anchor: nil)
    unless pull_comparison.is_a?(PullRequest::Comparison)
      raise TypeError, "expected pull_comparison to be a PullRequest::Comparison, but was #{pull_comparison.class}"
    end

    base_path = pull_request_path(pull_comparison.pull)

    path = if pull_comparison.range?
      "#{base_path}/files/#{pull_comparison.start_commit.oid}..#{pull_comparison.end_commit.oid}"
    else
      "#{base_path}/files/#{pull_comparison.end_commit.oid}"
    end

    path += "##{anchor}" if anchor
    path
  end

  def pull_request_review_state_classes(review)
    if T.unsafe(self).logged_in? && review
      "is-review-pending" if review.pending?
    end
  end

  def review_comments_count(review)
    return 0 unless review
    review.review_comments.with_pending_state.size
  end

  REVIEW_STATE_ICONS = {
    changes_requested: "file-diff",
  }.with_indifferent_access

  def review_state_octicon_name(state)
    REVIEW_STATE_ICONS.fetch(state)
  end

  def review_state_icon(state, options = {})
    T.unsafe(self).octicon(review_state_octicon_name(state), options)
  end

  def show_pull_request_reviews_hint?(pull_request)
    return false unless pull_request.base_branch_rule_evaluator&.pull_request_reviews_enabled?

    if pull_request.persisted?
      return false unless pull_request.open?

      review_decision = pull_request.cached_merge_state(viewer: T.unsafe(self).current_user).pull_request_review_policy_decision
      return !review_decision.rules_fulfilled?
    end

    true
  end

  def changes_requested_on_pull_request?(pull_request)
    return unless pull_request.base_branch_rule_evaluator&.pull_request_reviews_enabled?
    return unless pull_request.persisted?

    review_decision = pull_request.cached_merge_state(viewer: T.unsafe(self).current_user).pull_request_review_policy_decision
    review_decision.changes_requested?
  end
end
