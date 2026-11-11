# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :list_pull_requests do |access|
    access.ensure_context :repo
    access.allow(:everyone) { |context| context[:repo].public? }
    access.allow :repo_resources_reader
    access.allow :pull_request_reader
  end

  define_access :get_pull_request,
                :read_pull_request_hovercard,
                :list_pull_request_commits,
                :list_pull_request_files,
                :get_pull_request_merge_status,
                :get_pull_request_review_request,
                :list_pull_request_review_requests,
                :list_pull_request_comments,
                :get_pull_request_comment,
                :get_auto_merge,
                :get_merge_queue_entry,
                :get_pull_request_stack_entry do |access|
    resource_must_belong_to_repo(access)
    access.allow(:everyone) { |context| context[:repo].public? }
    access.allow :pull_request_reader
  end

  define_access :create_pull_request do |access|
    access.ensure_context(:repo) do |repo|
      PullRequestActivationConfig.new(repo).pull_requests_enabled?
    end

    access.allow(:pull_request_writer)

    access.allow(:repo_resources_reader) do |context|
      user, repo = extract(context, :user, :repo)
      actor = user.try(:installation) || user
      pull_request_creation_config = PullRequestCreationConfig.new(repo)

      next false unless actor && !actor.can_have_granular_permissions?
      next false unless pull_request_creation_config.pull_request_creation_allowed_for?(user)
      next true unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap, repo, default: false)

      next true unless context[:pull_request] # Some workflows use :create_pull_request as a generic permission check without creating a PR, so skip the PR cap for them.
      !pull_request_creation_config.pull_request_exceeds_limit?(context[:pull_request])
    end

    access.allow(:pull_requests_from_forks_writer) do |context|
      user, repo = extract(context, :user, :repo)
      actor = user.try(:installation) || user
      pull_request_creation_config = PullRequestCreationConfig.new(repo)

      next false unless pull_request_creation_config.pull_request_creation_allowed_for?(user)
      next true unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap, repo, default: false)

      next true unless context[:pull_request] # Some workflows use :create_pull_request as a generic permission check without creating a PR, so skip the PR cap for them.
      !pull_request_creation_config.pull_request_exceeds_limit?(context[:pull_request])
    end
  end

  define_access :update_pull_request do |access|
    resource_must_belong_to_repo(access)
    access.allow(:pull_request_author)
    access.allow(:pull_request_writer)
  end

  define_access :close_pull_request do |access|
    resource_must_belong_to_repo(access)
    access.allow(:pull_request_author)
    access.allow(:pull_request_writer)
    access.allow(:repo_triagger) { |context| issue_must_match_permission(context, :write) }
  end

  define_access :request_pull_request_review do |access|
    resource_must_belong_to_repo(access)
    access.allow(:pull_request_review_requester)
  end

  define_access :merge_pull_request,
                :enable_pull_request_auto_merge,
                :disable_pull_request_auto_merge,
                :enqueue_pull_request,
                :dequeue_pull_request do |access|
    resource_must_belong_to_repo(access)
    access.allow :repo_contents_writer
  end

  define_access :revert_pull_request do |access|
    resource_must_belong_to_repo(access)

    access.allow :repo_contents_writer do |context|
      user, repo = extract(context, :user, :repo)
      repo.resources.pull_requests.writable_by?(user)
    end
  end

  define_access :create_pull_request_comment do |access|
    resource_must_belong_to_repo(access)

    access.allow :pull_request_writer

    access.allow :repo_resources_reader do |context|
      user  = extract(context, :user)
      actor = user.try(:installation) || user
      actor && !actor.can_have_granular_permissions?
    end

    access.allow :pull_requests_comment_only_reviews_writer
  end

  define_access :update_pull_request_comment do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_comment_author
    access.allow :pull_request_writer
  end

  define_access :delete_pull_request_comment do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_comment_author
    access.allow :pull_request_writer
  end

  define_access :submit_pull_request_review do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_review_author
  end

  define_access :dismiss_pull_request_review do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_writer
  end

  define_access :delete_pull_request_review do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_review_author
  end

  define_access :resolve_pull_request_review_thread do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_author
    access.allow :repo_contents_writer
  end

  define_access :mark_pull_request_ready_for_review do |access|
    resource_must_belong_to_repo(access)
    access.allow :pull_request_author
    access.allow :repo_contents_writer
  end

  define_access :list_pull_request_stacks,
                :list_pull_request_stack_entries do |access|
    access.allow(:pull_request_reader)
  end

  define_access :create_pull_request_stack do |access|
    access.allow(:pull_request_writer)
  end

  define_access :update_pull_request_stack do |access|
    access.allow(:pull_request_writer)
  end

  define_access :delete_pull_request_stack do |access|
    access.allow(:pull_request_writer)
  end
end
