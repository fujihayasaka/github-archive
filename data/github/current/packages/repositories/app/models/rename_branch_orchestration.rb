# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

class RenameBranchOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  validate :can_rename?, on: :create

  protected def target_uniqueness_condition_on_start; end
  def validate_no_duplicates; end

  def can_rename?
    unless actor
      set_error_reason_on_rename("Could not determine current user")
      return
    end

    unless data[:raw_new_name]
      set_error_reason_on_rename(:invalid_new_name)
      return
    end

    if data[:raw_new_name].bytesize > 255 - "refs/heads/".bytesize
      set_error_reason_on_rename(:name_too_big)
      return
    end

    data[:clean_new_name] ||= Git::Ref.paste_safe_normalize(data[:raw_new_name])
    if data[:clean_new_name].blank?
      set_error_reason_on_rename(:invalid_new_name)
      return
    end

    # branches starting with refs/heads lead to erroneous behavior
    # these names must be deleted and recreated without refs/heads
    if old_name.starts_with?("refs/heads/")
      set_error_reason_on_rename(:invalid_old_name)
      return
    end

    data[:commit_oid] = repository.ref_to_sha(old_name)
    unless data[:commit_oid]
      set_error_reason_on_rename(:old_branch_has_no_commit)
      return
    end

    @rename = repository.branch_renames.new(
      old_name: old_name,
      new_name: data[:clean_new_name],
      user: actor,
      old_sha: commit_oid
    )

    pb = @rename&.protected_branch_to_update&.reload
    if pb && pb.branch_actor_allowances.map(&:actor).any?(&:nil?)
      set_error_reason_on_rename("there is an invalid protected branch bypass actor")
      return
    end

    unless @rename.valid?
      set_error_reason_on_rename(:rename_could_not_be_saved)
    end
  end

  step :create_rename_record do
    unless @rename.save
      set_error_reason_on_rename(:rename_could_not_be_saved)
      return :failed
    end

    data[:branch_rename_id] = @rename.id
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:start_rename_failed)
    return :failed, redact_sensitive_error(err)
  end

  step :copy_protected_branch do
    protected_branch = rename.protected_branch_to_update
    return if protected_branch.nil?

    protected_branch.deep_copy_as!(name: new_name, creator: actor, entry_point: data[:entry_point])
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:move_protected_branch_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :update_merge_queue do
    return true unless repository.merge_queue_enabled?

    new_protected_branch = repository.protected_branches.where(name: new_name).first
    new_protected_branch_queue = new_protected_branch&.merge_queue
    old_protected_branch_queue = rename.protected_branch_to_update&.merge_queue

    if old_protected_branch_queue || new_protected_branch_queue
      MergeQueue.transaction do
        # Cloning the branch protection will have implicitly created a new
        # `MergeQueue` instance. We want to replace this with the existing
        # instance, so that we preserve associated data (e.g. `MergeGroupStat`
        # records).
        new_protected_branch_queue&.destroy!

        old_protected_branch_queue&.update!(
          protected_branch_id: new_protected_branch.id,
          branch: new_name,
        )
      end
    elsif default_branch?
      # If there is no `MergeQueue` associated with the `ProtectedBranch`,
      # there might still be a queue associated with a `RepositoryRuleset`.
      # If that ruleset uses the generic `~DEFAULT_BRANCH` target, and we're
      # renaming the default branch, that queue will need to be updated.
      MergeQueues.handle_default_branch_rename!(repository:, old_name:, new_name:)
    end
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:update_merge_queue_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :create_new_branch do
    repository.heads.create(new_name, old_sha, actor)
  rescue => err # rubocop:todo Lint/GenericRescue
    case err
    when Git::Ref::ProtectedBranchUpdateError
      set_error_reason_on_rename(:create_protected_branch_exception)
      return :skipped, redact_sensitive_error(err)
    when Git::Ref::RepositoryRuleViolationError
      set_error_reason_on_rename(:repository_rule_violation)
      return :skipped, redact_sensitive_error(err)
    when Git::Ref::ExistsError
      set_error_reason_on_rename(:new_branch_already_exists)
      return :skipped, redact_sensitive_error(err)
    when Git::Ref::HookFailed # pre-receive hook failure
      set_error_reason_on_rename(:new_branch_hook_failure)
      return :skipped, redact_sensitive_error(err)
    when Git::Ref::InvalidName, Git::Ref::UpdateFailed
      set_error_reason_on_rename(:new_branch_invalid_name)
      return :skipped, redact_sensitive_error(err)
    when GitHub::DGit::Error
      set_error_reason_on_rename(:new_branch_dgit_error)
    else
      set_error_reason_on_rename(:start_rename_failed)
    end
    return :failed, redact_sensitive_error(err)
  end

  job_start

  step :should_run_job do
    return :skipped, "Branch already renamed" if rename&.finished?
    return :failed, "Branch rename never started" unless rename&.started?
  end

  step :update_default_branch do
    return unless default_branch?
    return if repository.default_branch == new_name

    success = measure_time(:update_default_branch) do
      repository.point_to_new_default_branch(new_name)
    end

    unless success
      set_error_reason_on_rename(:failed_to_update_default_branch)
      return :failed, :failed_to_update_default_branch
    end
  rescue => err # rubocop:todo Lint/GenericRescue
    case err
    when GitHub::DGit::Error
      set_error_reason_on_rename(:update_default_branch_dgit_error)
    when GitRPC::Timeout
      set_error_reason_on_rename(:update_default_branch_gitrpc_timeout)
    else
      set_error_reason_on_rename(:update_default_branch_exception)
    end
    return :failed, redact_sensitive_error(err)
  end

  step :update_indexes_to_new_default_branch do
    return unless default_branch?

    success = measure_time(:update_indexes_to_new_default_branch) do
      repository.update_indexes_to_new_default_branch(old_name, new_name)
    end

    unless success
      set_error_reason_on_rename(:failed_to_update_default_branch)
      return :failed, :failed_to_update_default_branch
    end
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:update_indexes_to_new_default_branch_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :check_repository_writable do
    unless repository.writable?
      set_error_reason_on_rename(:unwritable_repository)
      return :failed, "#{repository.name_with_display_owner} is archived, migrating, or disabled"
    end
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:check_repository_writable_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :retarget_open_pull_requests do
    failed_pr_retarget_count = 0

    measure_time(:retarget_open_pull_requests) do
      rename.pull_requests_to_retarget.find_each do |pr|
        # Don't mark the rename process as having failed if a PR can't be automatically
        # retargeted. This is because the new branch has been created and marked as
        # the default at this point, if the old branch had been the default, so the
        # bulk of the work has been done and the new branch can start being used.
        unless change_pull_request_base_branch(pr)
          failed_pr_retarget_count += 1
        end
      end
    end

    data[:failed_pr_retarget_count] = failed_pr_retarget_count
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:retarget_open_pull_requests_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :retarget_draft_releases do
    releases = rename.draft_releases_to_retarget
    return if releases.empty?

    releases.update_all(target_commitish: new_name)
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:retarget_draft_releases_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :update_pages_branch do
    return unless rename.update_pages?

    page = repository.page
    page.set_source(ref_name: new_name, subdir: page.source_subdir)
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:update_pages_branch_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :delete_old_branch_if_appropriate do
    return unless should_delete_old_branch?

    ref = repository.heads.find(old_name)
    return if ref.nil? || !ref.exist? # our work is done!

    unless ref.deleteable_to_complete_rename?
      set_error_reason_on_rename(:old_branch_not_deletable)
      return :failed, :old_branch_not_deletable
    end

    ref.delete(user, allow_deletion_policy_bypass: true)
  rescue => err # rubocop:todo Lint/GenericRescue
    case err
    when GitHub::DGit::ThreepcFailedToLock,
         GitHub::DGit::UnroutedError,
         GitHub::DGit::InsufficientQuorumError
      set_error_reason_on_rename(:old_branch_dgit_error)
    when Git::Ref::HookFailed # pre-receive hook failure
      set_error_reason_on_rename(:old_branch_hook_failure)
    else
      set_error_reason_on_rename(:delete_old_branch_if_appropriate_exception)
    end
    return :failed, redact_sensitive_error(err)
  end

  step :remove_old_protected_branch do
    rename.protected_branch_to_update&.destroy
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:delete_old_protected_branch_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :mark_rename_as_finished do
    unless rename.update(state: :finished)
      return :failed, :rename_could_not_be_saved
    end
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:mark_rename_as_finished_exception)
    return :failed, redact_sensitive_error(err)
  end

  step :mark_obsolete_renames_as_moot do
    RepositoryBranchRename.get_by_repo_and_old_name(repository_id: repository.id, old_name: rename.new_name)
                          .update_all(state: :moot)
  rescue => err # rubocop:todo Lint/GenericRescue
    set_error_reason_on_rename(:mark_obsolete_renames_as_moot_exception)
    return :failed, redact_sensitive_error(err)
  end

  def rename
    return @rename if defined?(@rename)
    @rename = RepositoryBranchRename.find_by_id(data[:branch_rename_id])
  end

  def human_error
    if error == :rename_could_not_be_saved
      rename.errors.full_messages.to_sentence
    elsif error == :old_branch_has_no_commit
      "branch #{old_name} has no commits"
    elsif error == :invalid_new_name
      "not a valid name for a branch"
    elsif error == :invalid_old_name
      "branch must be deleted and recreated"
    elsif error == :name_too_big
      "Sorry, refs longer than 255 bytes are not allowed."
    elsif rename&.error_reason
      rename.human_error_reason
    else
      error.to_s
    end
  end

  def error
    return @error if defined?(@error)
    return rename&.error_reason.to_sym if rename&.error_reason
    nil
  end

  private

  memoize def actor
    User.find_by_id(data[:actor_id])
  end

  def old_name
    data[:old_name]
  end

  def commit_oid
    data[:commit_oid]
  end

  def new_name
    rename&.new_name
  end

  def user
    rename&.user
  end

  def default_branch?
    rename&.default_branch?
  end

  def old_sha
    rename&.old_sha
  end

  # Only delete the old branch when all the PRs that were pointing to it were successfully retargeted to point to
  # the new branch. This is to give some control to the user and not auto-close those PRs due to the old branch
  # being deleted.
  def should_delete_old_branch?
    data[:failed_pr_retarget_count] < 1
  end

  def set_error_reason_on_rename(error_reason)
    if rename&.id
      rename.update!(state: :errored, error_reason: error_reason)
    else
      @error = error_reason
      self.errors.add(:base, error_reason)
    end
  end

  def change_pull_request_base_branch(pr)
    prior_base_display_name = pr.display_base_ref_name
    pr.rename_base_branch(new_name)
  rescue ActiveRecord::ActiveRecordError => err
    Failbot.report(err, pull_request_id: pr.id)
    mark_pr_retarget_as_failing
    GitHub.dogstats.increment("rename_branch.failed_pr_retargets",
      tags: ["visibility:#{repository.visibility}",
             "error:active-record"])
    false
  rescue PullRequest::BaseNotChangeableError => err1
    Failbot.report(err1, pull_request_id: pr.id)
    mark_pr_retarget_as_failing
    GitHub.dogstats.increment("rename_branch.failed_pr_retargets",
      tags: ["visibility:#{repository.visibility}",
             "error:base-not-changeable"])

    begin
      pr.create_issue_event(:automatic_base_change_failed, user,
        message: err1.error_type_key,
        title_was: prior_base_display_name,
        title_is: new_name)
    rescue ActiveRecord::ActiveRecordError => err2
      Failbot.report(err2, pull_request_id: pr.id)
    end

    false
  rescue GitRPC::ObjectMissing => err3
    Failbot.report(err3, pull_request_id: pr.id)
    mark_pr_retarget_as_failing
    GitHub.dogstats.increment("rename_branch.failed_pr_retargets",
      tags: ["visibility:#{repository.visibility}",
             "error:gitrpc-object-missing"])
    false
  end

  def mark_pr_retarget_as_failing
    rename.update!(error_reason: :pull_request_retarget_failed)
  rescue ActiveRecord::ActiveRecordError => err
    Failbot.report(err)
  end

  def measure_time(key)
    GitHub.dogstats.time("rename_branch.#{key}.time") do
      yield
    end
  end

  def redact_sensitive_error(exception)
    "#{exception.class.name}: #{exception.needs_redacting? ? "[redacted]" : exception.message}"
  end
end
