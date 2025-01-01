# typed: true
# frozen_string_literal: true

class CloneTemplateOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  validate :valid_orchestration, on: :create

  protected def target_uniqueness_condition_on_start; end

  def skip_repository_id_validation
    true
  end

  def valid_orchestration
    unless template_repository&.resources&.contents&.readable_by?(actor)
      errors.add(:base, "template repository not found.")
      return
    end

    unless template_repository.template?
      errors.add(:base, "#{template_repository.name_with_display_owner} is not a template repository.")
      return
    end

    unless template_repository.active?
      errors.add(:base, "#{template_repository.name_with_display_owner} is no longer active.")
      return
    end

    if template_repository.disabled_at.present? || template_repository.disabled_access_reason
      errors.add(:base, "#{template_repository.name_with_display_owner} has been disabled and cannot be used " \
                "as a template.")
      return
    end

    if repository.present? && !repository&.empty?
      errors.add(:base, "#{repository&.name_with_display_owner} already has content.")
      return
    end

    if template_repository.empty?
      errors.add(:base, "#{template_repository.name_with_display_owner} is empty.")
      return
    end

    # make sure that if we are going to create a new repo, the creation passes all input validation ahead of time
    if create_orchestration&.errors&.any?
      if create_orchestration.built_repository&.errors&.any?
        errors.add(:base, create_orchestration.built_repository.errors.full_messages.to_sentence)
      elsif create_orchestration.allowed == false
        errors.add(:base, "#{actor} does not have permission to create a repository owned by #{owner}")
      else
        errors.add(:base, create_orchestration.errors.full_messages.to_sentence)
      end

      nil
    end
  end

  step :create_repository, max_attempts: 1 do
    if create_orchestration.present?
      create_orchestration.execute

      return :skipped, "create orchestration ID: #{create_orchestration.id} skipped" if create_orchestration.skipped?

      unless create_orchestration.succeeded? || create_orchestration.running?
        return :failed, "create orchestration ID: #{create_orchestration.id} failed: #{create_orchestration.error_message}"
      end

      update!(repository: create_orchestration.repository)
    end
  end

  step :create_repository_clone do
    return :skipped, "repository deleted" if repository_after_create.deleted?

    clone = RepositoryClone.new(
      clone_repository: repository,
      template_repository: template_repository,
      cloning_user: actor
    )

    unless clone.save
      return :failed, clone.errors.full_messages.join(", ")
    end

    data.merge!({ repo_clone_id: clone.id })
  end

  job_start

  step :validate_repository_clone do
    return :skipped, "repository deleted" if repository_after_create.deleted?

    unless repo_clone.present?
      return :failed, "Clone with id #{data[:repo_clone_id]} was not found."
    end

    if template_repository.disk_usage > RepositoryClone::MAX_REPO_DISK_USAGE_IN_KILOBYTES.kilobytes
      set_error_on_repo_clone(:repo_size_too_large)
      return :failed, "active template repo too large"
    end
  end

  step :copy_branches do
    return :skipped, "repository deleted" if repository_after_create.deleted?

    branches_to_copy = [template_repository.default_branch.b]
    branches_to_copy.concat(get_other_branch_names_for(template_repository)) if copy_branches?

    branches_to_copy.each do |branch_name|
      copied, error = copy_branch(branch_name, template_repo: template_repository, target_repo: repository, author: repo_clone.cloning_user)
      unless copied
        set_error_on_repo_clone(error)
        return :skipped, "rule violations prevented branch copy" if error == :rule_violations

        return :failed, "copy branch failed: #{error}"
      end
    end
  rescue GitHub::DGit::Error => e
    set_error_on_repo_clone(:dgit_exception)
    raise
  rescue GitRPC::Error => e
    set_error_on_repo_clone(:gitrpc_exception)
    raise
  end

  step :set_default_branch do
    return :skipped, "repository deleted" if repository_after_create.deleted?

    new_default_branch = template_repository.default_branch.b
    return if repository_after_create.default_branch.b == new_default_branch

    unless repository_after_create.update_default_branch(new_default_branch, raise_on_failure: true)
      if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
        Repositories.domain.reload(repository_after_create)
      else
        repository_after_create.reload
      end
      if repository_after_create.default_branch.b == new_default_branch
        log_info("Orchestration attempted to update default branch to current value")
        return
      end

      set_error_on_repo_clone(:failed_to_update_branch)
      return :failed, "failed to update default branch"
    end
  rescue Repository::FailedDefaultBranchUpdateError => e
    set_error_on_repo_clone(:failed_to_update_branch)
    raise
  rescue GitHub::DGit::Error => e
    set_error_on_repo_clone(:dgit_exception)
    raise
  rescue GitRPC::Error => e
    set_error_on_repo_clone(:gitrpc_exception)
    raise
  end

  step :final_validation do
    return :skipped, "repository deleted" if repository_after_create.deleted?

    repo_clone.state = :finished

    unless repo_clone.save
      repo_clone.update_attribute(:state, :error)
      repo_clone.update_attribute(:error_reason_code, :cannot_finish)

      return :failed, "final validation failure: #{repo_clone.errors.full_messages.to_sentence}"
    end
  end

  memoize def template_repository
    if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(data[:template_repository_id].to_i)
    else
      Repository.find_by(id: data[:template_repository_id])
    end
  end

  memoize def repo_clone
    RepositoryClone.find_by(id: data[:repo_clone_id])
  end

  memoize def owner
    User.find_by(id: data[:owner_id]) || repository&.owner
  end

  memoize def copy_branches?
    data[:copy_branches] || false
  end

  def name
    data[:name] || repository&.name
  end

  def name_with_owner
    "#{owner.login}/#{name}"
  end

  def public?
    if new_repository_attributes&.key?(:public)
      new_repository_attributes[:public]
    else
      repository&.public?
    end
  end

  def create_orchestration
    return if repository.present?
    return @create_orchestration if defined?(@create_orchestration)

    reflog_data = (new_repository_attributes&.dig(:reflog_data) || {}).merge(
      repo_name: name_with_owner,
      repo_public: public?
    )

    repo_attributes = (new_repository_attributes || {}).merge(owner: owner, name: name)

    @create_orchestration = RepositoryOrchestration.create_repository(
      actor:,
      owner_login: owner.login,
      repo_attributes:,
      reflog_data:,
      current_integration_context: @current_integration_context,
    )
  end

  attr_accessor :new_repository_attributes
  attr_writer :actor
  attr_writer :current_integration_context

  sig { returns(Repository) }
  def repository_after_create
    T.must(repository)
  end

  private

  attr_reader :actor

  # Private: Get a list of non-default branches in the given repository.
  #
  # repo - a Repository
  #
  # Returns an Array of Strings.
  def get_other_branch_names_for(repo)
    branch_indicator_prefix = "refs/heads/"
    repo.rpc.raw_branch_names_and_dates.map { |_, ref_name| ref_name }. # all refs
        select { |ref_name| ref_name.start_with?(branch_indicator_prefix) }. # just the branches
        map { |ref_name| ref_name.split(branch_indicator_prefix).last.b }. # drop 'refs/heads/' prefix
        reject { |branch_name| branch_name == repo.default_branch.b } # default branch is already copied
  end

  # Private: "Copies branch" from template repo to target repo by fetching git
  # data for the given branch from the template repo into the target repo, then
  # creating a new commit on the target repo from the given branch's tree oid.
  #
  # Returns error if:
  # - Branch doesn't exist in the template repo
  # - Branch contains too many files (see RepositoryClone::MAX_TEMPLATE_FILE_LIMIT)
  #
  # Returns true if branch was copied successfully, false otherwise, along with an error code.
  def copy_branch(branch_name, template_repo:, target_repo:, author:)
    template_ref = template_repo.refs.find(branch_name)

    if template_ref.nil?
      return false, :no_commit_oid
    end

    _tree_oid, tree_entries, truncated = template_repo.tree_entries(template_ref.target_oid, "",
      recursive: true, limit: RepositoryClone::MAX_TEMPLATE_FILE_LIMIT, skip_size: false)

    if truncated # tree_entries call returned more than 100_000 files
      return false, "too many files for template repo branch"
    end

    target_repo.rpc.fetch(template_repo.internal_remote_url, refspec: "refs/heads/#{branch_name}")

    tree_oid = template_ref.target.tree_oid

    commit_details = {
      message: commit_message_for(branch_name, default_branch: template_repo.default_branch),
      author: author, # Author is the authenticated user who initiated the clone, while the committer will be GitHub
      tree: tree_oid
    }

    base_ref = target_repo.heads.find_or_build(branch_name)

    begin
      base_ref.append_commit(commit_details, author, sign: true)
      true
    rescue Git::Ref::ProtectedBranchUpdateError => e
      [false, :rule_violations]
    rescue Git::Ref::RepositoryRuleViolationError => e
      target_repo.set_repo_clone_rule_suite_id(e.rule_suite.id, actor: author)
      [false, :rule_violations]
    end
  end

  # commit message for the new/default branch
  def commit_message_for(branch_name, default_branch:)
    if branch_name == default_branch
      "Initial commit"
    else
      "Initialize #{branch_name}"
    end
  end

  # sets the error_reason_code on the RepositoryClone model
  def set_error_on_repo_clone(error)
    return unless repo_clone
    repo_clone.state = :error
    error_reason_code = RepositoryClone.error_reason_codes[error] ? error : :other_exception
    repo_clone.error_reason_code = error_reason_code
    repo_clone.save(validate: false)
  end
end
