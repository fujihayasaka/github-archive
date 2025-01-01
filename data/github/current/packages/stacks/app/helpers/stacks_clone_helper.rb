# typed: true
# frozen_string_literal: true

# Helper class to clone contents of a given ref from template repository
# Code referred from app/jobs/clone_template_repository_files_job.rb

class StacksCloneHelper
  GITHUB_STACKS_FOLDER_PATH = ".github/stacks"
  DEFAULT_BRANCH_COMMIT_MESSAGE = "Initial commit"

  MAX_REPO_DISK_USAGE_IN_KILOBYTES = RepositoryClone::MAX_REPO_DISK_USAGE_IN_KILOBYTES
  MAX_TEMPLATE_FILE_LIMIT = RepositoryClone::MAX_TEMPLATE_FILE_LIMIT

  def clone_ref(stack_instance, ref_to_clone = nil)
    method_name = "#{self.class.name}##{__method__}"
    log_and_raise(method_name, "missing stack instance", :missing_stack_instance) if stack_instance.nil?

    @template_repo_id = stack_instance.template_repository_id
    @target_repo_id = stack_instance.instance_repository_id

    unless (template_repo = stack_instance&.template_repository)&.active?
      log_and_raise(method_name, "missing active template repo", :missing_template_repo)
    end

    unless target_repo = stack_instance.instance_repository
      log_and_raise(method_name, "missing clone repository", :missing_clone_repo)
    end

    if stack_instance.template_repository.disk_usage > MAX_REPO_DISK_USAGE_IN_KILOBYTES.kilobytes
      log_and_raise(method_name, "active template repo too large", :repo_size_too_large)
    end

    if !ref_to_clone
      ref_to_clone = template_repo.default_branch.b
    end

    copy_ref(ref_to_clone, template_repo.default_branch.b, template_repo: template_repo, target_repo: target_repo, author: stack_instance.actor)

    set_default_branch(stack_instance)
    push_cloning_status_metric "success"
    rescue => e # rubocop:todo Lint/RescueException
      push_cloning_status_metric "error"
      GitHub::Logger.log_exception(
        { fn: method_name, template_repo_id: @template_repo_id, target_repo_id: @target_repo_id }, e)
      raise
  end

  private

  def set_default_branch(stack_instance)
    template_repo = stack_instance.template_repository
    target_repo = stack_instance.instance_repository
    new_default_branch = template_repo.default_branch.b
    return if target_repo.default_branch.b == new_default_branch

    unless target_repo.update_default_branch(new_default_branch)
      log_and_raise("#{self.class.name}##{__method__}", "failed to update default branch", :failed_to_update_branch)
    end
  end

  def copy_ref(ref_to_clone, branch_name, template_repo:, target_repo:, author:)
    method_name = "#{self.class.name}##{__method__}"
    template_ref = template_repo.refs.find(ref_to_clone)
    if template_ref.nil?
      log_and_raise(method_name, "no commit oid for stack repo ref", :no_commit_oid)
    end

    _tree_oid, tree_entries, truncated = template_repo.tree_entries(template_ref.target_oid, "",
      recursive: true, limit: RepositoryClone::MAX_TEMPLATE_FILE_LIMIT, skip_size: false)

    if truncated # tree_entries call returned more than 100_000 files
      log_and_raise(method_name, "too many files for stack repo ref", :other_exception)
    end

    target_repo.rpc.fetch(template_repo.internal_remote_url, refspec: ref_to_clone)

    new_tree_sha = StackignoreHelper.new.remove_ignored_files(target_repo, template_ref.target.tree_oid)

    commit_details = {
      message: DEFAULT_BRANCH_COMMIT_MESSAGE,
      author: author, # Author is the authenticated user who initiated the clone, while the committer will be GitHub
      tree: new_tree_sha
    }

    base_ref = target_repo.heads.find_or_build(branch_name)

    base_ref.append_commit(commit_details, author, sign: true)
  end

  def push_cloning_status_metric(status)
    Metrics.push_metric Metrics::INCREMENT, Component::STEP, "repo_clone", "status", tags: ["action:#{status}"]
  end

  def log_and_raise(method, err_msg, err_code)
    if @template_repo_id.nil? && @target_repo_id.nil?
      GitHub::Logger.error(fn: method,
        message: err_msg)
    else
      GitHub::Logger.error(fn: method,
        message: err_msg,
        template_repo_id: @template_repo_id,
        target_repo_id: @target_repo_id)
    end
    raise Errors::CloneError.new(err_msg, err_code)
  end
end
