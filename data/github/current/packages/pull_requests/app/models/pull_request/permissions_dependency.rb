# typed: true
# frozen_string_literal: true

module PullRequest::PermissionsDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { PullRequest }

  class_methods do
    # Determines the target for for conditional access for multiple pull requests
    #
    # pulls - an enumerable of PullRequest
    #
    # returns Hash[PullRequest] => target for conditional access
    def multiple_target_for_conditional_access(pulls)
      ConditionalAccess::Filter.ensure_with_class(pulls, PullRequest)

      repositories = Repository.where(id: pulls.map { |pull| pull.repository_id })
      repository_to_target = Repository.multiple_target_for_conditional_access(repositories)

      repository_id_to_target = repository_to_target.transform_keys { |k| k.id }
      pulls.each_with_object({}) { |v, h| h[v] = repository_id_to_target[v.repository_id] }
    end
  end

  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  def async_target_for_conditional_access
    async_repository.then(&:async_target_for_conditional_access)
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_readable_by?(actor)
    @async_readable_by ||= Hash.new do |h, key|
      h[key] = async_repository.then do |repository|
        next false unless repository

        repository.resources.pull_requests.async_readable_by?(key)
      end
    end
    @async_readable_by[actor]
  end

  def labelable_by?(actor:)
    async_labelable_by?(actor: actor).sync
  end

  def async_labelable_by?(actor:)
    async_issue.then do |issue|
      next false unless issue.present?
      issue.async_labelable_by?(actor: actor)
    end
  end

  # Public: Determine if this pull request's repository is readable by the given user.
  #
  # user - a User
  #
  # Returns a Promise that resolves to a Boolean.
  def async_repository_metadata_readable_by?(user)
    async_repository.then do |repo|
      repo.resources.metadata.readable_by?(user)
    end
  end

  def async_base_repository_pushable_by?(user)
    async_base_repository.then do |base_repo|
      (base_repo&.async_writable_by?(user) || Promise.resolve(false))
    end
  end

  def async_can_merge_as_admin?(user)
    async_base_repository.then do |repo|
      repo.async_owner.then do
        async_batch_base_branch_rule_evaluator.then do |base_branch_rule_evaluator|
          next false unless base_branch_rule_evaluator
          base_branch_rule_evaluator.can_merge_as_admin?(actor: user)
        end
      end
    end
  end

  # Public: Determine if this pull request's head repository is pushable by the
  #         given user, where "pushable" is defined as write access to the head
  #         repository's git contents
  #
  # user - a User
  #
  # Returns a Promise that resolves to a Boolean.
  def async_head_repository_pushable_by?(user)
    async_head_repository.then do |head_repo|
      next false unless head_repo
      head_repo.resources.contents.async_writable_by?(user)
    end
  end

  def head_ref_pushable_by?(user)
    return false unless head_repository
    T.must(head_repository).pushable_by?(user, ref: head_ref)
  end

  def head_repository_pullable_by?(user)
    return false unless head_repository
    T.must(head_repository).pullable_by?(user)
  end

  def head_ref_restorable_by?(user)
    async_head_ref_restorable_by?(user).sync
  end

  # Checks if the provided user has permission to restore the PR's head ref
  def async_head_ref_restorable_by?(user)
    @async_head_ref_restorable_by ||= {}
    return @async_head_ref_restorable_by[user] if @async_head_ref_restorable_by.has_key?(user)

    @async_head_ref_restorable_by[user] ||= async_head_ref_restorable_by!(user)
  end

  def async_head_ref_restorable_by!(user)
    return Promise.resolve(false) unless head_ref

    async_repository.then do |repo|
      next false if repo.locked_on_migration?

      async_head_repository.then do |head_repo|
        next false unless head_repo
        head_repo.async_network.then do
          next false if head_repo.heads.exist?(head_ref)
          async_head_repository_pushable_by?(user)
        end
      end
    end
  end

  def allowed?
    repository.permit?(user, :write)
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_update_reasons(viewer)
    async_issue.then { |issue| issue.async_viewer_cannot_update_reasons(viewer) }
  end

  def user_unable_to_create_pr?
    !user_able_to_create_pr?
  end

  def user_able_to_create_pr?
    return false unless (repo = repository) && user
    return true if GitHub.enterprise?
    return true if repo.nwo == AdvisoryDB::ADVISORIES_REPOSITORY_NWO # rubocop:disable GitHub/DoNotAllowNameWithOwner
    return true unless repo.public?
    return true if user.is_a?(Bot)
    repo_owner = T.must(repo.owner)
    if repo_owner.organization?
      repo_owner = T.cast(repo_owner, Organization)
      return true if repo_owner.member?(user)
    end
    return true if head_repository&.pushable_by?(user) || base_repository&.pushable_by?(user)
    return true if repo.direct_role_for(user)

    false
  end

  def suggested_change_applicable_by?(committer)
    return false unless committer

    @suggested_change_applicable_by ||= {}
    return @suggested_change_applicable_by[committer.id] if @suggested_change_applicable_by.key?(committer.id)

    @suggested_change_applicable_by[committer.id] = async_head_repository.then do |head_repo|
      next false unless head_repo
      head_repo.pushable_by?(committer, ref: head_ref_name)
    end.sync
  end

  # Can the user add a PR to the Merge Queue?
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_add_to_merge_queue?(user)
    async_repository.then do |repo|
      repo.can_add_pull_requests_to_merge_queue?(user, branch_name: base_ref_name)
    end
  end

  # Can the user add a PR to the Merge Queue?
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_add_to_merge_queue?(user)
    async_can_add_to_merge_queue?(user).sync
  end

  # Can the user access the Jump feature of Merge Queue?
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_jump_merge_queue?(user)
    async_can_jump_merge_queue?(user).sync
  end

  # Can the user access the Jump feature of Merge Queue?
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_jump_merge_queue?(user)
    return Promise.resolve(T.let(false, T::Boolean)) if user.nil?

    async_repository.then do |repo|
      repo.async_owner.then do |repo_owner|
        if MergeQueues.uses_fgp?(repo_owner)
          Platform::Loaders::Permissions::BatchAuthorize.load(
            action: "jump_merge_queue",
            actor: user,
            subject: repo,
          ).then(&:allow?)
        else
          repo.async_action_or_role_level_for(user, include_custom_roles: false).then do |permission|
            [:maintain, :admin].include?(permission)
          end
        end
      end
    end
  end

  # Can the user access the Solo feature of Merge Queue?
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def can_add_to_merge_queue_solo?(user)
    async_can_add_to_merge_queue_solo?(user).sync
  end

  # Can the user access the Solo feature of Merge Queue?
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_can_add_to_merge_queue_solo?(user)
    return Promise.resolve(T.let(false, T::Boolean)) if user.nil?

    async_repository.then do |repo|
      repo.async_owner.then do |repo_owner|
        if MergeQueues.uses_fgp?(repo_owner)
          Platform::Loaders::Permissions::BatchAuthorize.load(
            action: "create_solo_merge_queue_entry",
            actor: user,
            subject: repo
          ).then(&:allow?)
        else
          repo.async_writable_by?(user)
        end
      end
    end
  end

  # Does the user have permission to edit files for this pull request?
  #
  # Returns: Boolean
  def async_files_editable_by?(user)
    return Promise.resolve(false) unless head_ref

    Promise.all([async_repository, async_head_repository]).then do |repo, head_repo|
      next false unless repo && head_repo
      next false if repo.locked_on_migration?
      head_repo.async_network.then do
        next false unless head_repo.heads.exist?(head_ref)
        async_head_repository_pushable_by?(user)
      end
    end
  end

  # Does the user have permission to update branch on the pull request?
  #
  # Returns: Boolean
  def async_branch_is_updatable_by?(user)
    return Promise.resolve(false) unless user
    return Promise.resolve(false) if user.must_verify_email?

    Promise.all([
      async_in_merge_queue?,
      async_head_repository,
      async_base_repository,
      async_head_user,
      async_base_user,
      async_batch_base_branch_rule_evaluator
    ]).then do |in_merge_queue, head_repo, base_repo, _head_user, _base_user, policy_evaluator|
      next false if in_merge_queue
      next false unless head_repo

      Promise.all([head_repo.async_owner, head_repo.async_network, base_repo.async_network]).then do |head_repo_owner, _, _|
        next false unless head_repo_owner
        next false unless head_repo.pushable_by?(user, ref: head_ref_name)

        strict_required_status_checks_enabled =
          policy_evaluator.present? &&
          policy_evaluator.required_status_checks_enabled? &&
          policy_evaluator.strict_required_status_checks_policy? &&
          policy_evaluator.required_status_checks.any?

        next false unless strict_required_status_checks_enabled || base_repo.enable_update_branch?

        next !!behind_base?
      end
    end
  end

  private

  # Validate that the actor is allowed to create pull requests.
  def validate_authorized_to_create_content(actor: user)
    content_authorization = ContentAuthorizer.authorize(actor, :pull_request, :create,
                                                        issue: issue,
                                                        repo: repository)
    return if content_authorization.authorized?
    content_authorization.errors.each do |error|
      errors.add(:base, error.message)
    end
  end

  def validate_refs_readable
    unless repository && comparison && comparison.viewable_by?(user)
      errors.add(:base, "not all refs are readable")
    end
  end
end
