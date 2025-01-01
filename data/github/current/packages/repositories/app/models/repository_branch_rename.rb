# typed: true
# frozen_string_literal: true

class RepositoryBranchRename < ApplicationRecord::Domain::Repositories
  include Instrumentation::Model
  include GitHub::Validations

  belongs_to :user
  belongs_to :repository, required: true
  destroy_in_background_with :repository

  before_validation :set_default_branch, on: :create

  after_update_commit :instrument_finished, if: :finished? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :instrument_errored, if: :errored? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :log_hydro_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates :user, presence: true, on: :create
  validates :old_name, :new_name, presence: true, bytesize: { maximum: 1024 }
  validate :ensure_names_differ
  validate :ensure_old_branch_exists, on: :create
  validate :ensure_new_branch_does_not_exist, on: :create
  validate :ensure_repo_writable, on: :create
  validate :ensure_no_branch_protection_rules_for_new_name, on: :create

  enum :state, {
    started: 0,
    finished: 1,
    errored: 2,
    # If you rename 'master' to 'main', then rename 'main' back to 'master', the initial rename will be marked moot.
    moot: 4,
    # default_branch_updated: 3 -- deprecated
  }

  scope :for_old_name, ->(name) { where(old_name: name) }
  scope :for_new_name, ->(name) { where(new_name: name) }
  scope :for_old_or_new_name, ->(name) { where("old_name = ? OR new_name = ?", name, name) }
  scope :latest, -> { order(id: :desc) }
  scope :since, ->(date) { where("repository_branch_renames.updated_at >= ?", date) }

  enum :error_reason, {
    # old_branch_has_no_commit: 0 -- deprecated
    old_branch_does_not_exist: 1,
    old_branch_not_deletable: 2,
    old_branch_hook_failure: 3,
    old_branch_dgit_error: 4,
    new_branch_already_exists: 5,
    new_branch_invalid_name: 6,
    new_branch_hook_failure: 7,
    new_branch_dgit_error: 8,
    failed_to_update_default_branch: 9,
    pull_request_retarget_failed: 10,
    unwritable_repository: 11,
    finish_rename_failed: 12,
    start_rename_failed: 13,
    update_default_branch_dgit_error: 14,
    update_default_branch_gitrpc_timeout: 15,

    # Reasons for uncaught exceptions that were previously subsumed under `finish_rename_failed`:
    update_default_branch_exception: 16,
    update_indexes_to_new_default_branch_exception: 17,
    check_repository_writable_exception: 18,
    retarget_open_pull_requests_exception: 19,
    retarget_draft_releases_exception: 20,
    update_merge_queue_exception: 21,
    delete_old_protected_branch_exception: 22,
    update_pages_branch_exception: 23,
    delete_old_branch_if_appropriate_exception: 24,
    mark_rename_as_finished_exception: 25,
    mark_obsolete_renames_as_moot_exception: 26,

    move_protected_branch_exception: 27,
    create_protected_branch_exception: 28,
    repository_rule_violation: 29,
  }

  def start_rename_failed?
    # Catch-all failure:
    return true if error_reason == "start_rename_failed"

    return true if update_merge_queue_exception? ||
                   move_protected_branch_exception?

    false
  end

  def finish_rename_failed?
    return false if error_reason.nil?

    # Catch-all failure:
    return true if error_reason == "finish_rename_failed"

    # Generic exceptions for substeps of `finish_rename`:
    return true if update_indexes_to_new_default_branch_exception? ||
                   check_repository_writable_exception? ||
                   retarget_open_pull_requests_exception? ||
                   retarget_draft_releases_exception? ||
                   delete_old_protected_branch_exception? ||
                   update_pages_branch_exception? ||
                   delete_old_branch_if_appropriate_exception? ||
                   mark_rename_as_finished_exception? ||
                   mark_obsolete_renames_as_moot_exception? ||
                   move_protected_branch_exception?

    # Other (handled) errors which can occur during substeps:
    return true if unwritable_repository? ||
                   old_branch_dgit_error? ||
                   old_branch_hook_failure?

    false
  end

  # Public: Returns the old branch name tagged as UTF-8 and scrubbed.
  def old_name_for_display
    @old_name_for_display ||= Git::Ref.value_for_display(old_name)
  end

  # Public: Returns the new branch name tagged as UTF-8 and scrubbed.
  def new_name_for_display
    @new_name_for_display ||= Git::Ref.value_for_display(new_name)
  end

  # Public: Get the branch protection rule that needs to be updated for this rename.
  # Will only match a rule that explicitly targets the branch being renamed; wildcard
  # rules are ignored.
  def protected_branch_to_update
    T.must(repository).protected_branches.where(name: old_name).first
  end

  # Public: Will the rename update GitHub Pages for this repository?
  def update_pages?
    repository&.page && repository&.pages_branch == old_name
  end

  # Public: Get all the releases whose target is the branch being renamed.
  def draft_releases_to_retarget
    base_query = T.must(repository).releases.draft
    releases = base_query.where(target_commitish: old_name)
    releases = releases.or(base_query.where(target_commitish: nil)) if default_branch?
    releases
  end

  # Public: Get all the pull requests whose head branch is the branch being renamed.
  def pull_requests_that_will_be_closed
    affected_pull_requests.from_repository(repository).where(head_ref: old_name)
  end

  # Public: Get all the pull requests whose base branch is the branch being renamed.
  def pull_requests_to_retarget
    affected_pull_requests.where(base_ref: old_name)
  end

  # Public: Get a count of how many pull requests will have their base branches updated, as
  # well as how many different repositories are represented.
  #
  # Returns a Hash of Repository ID => count of pull requests.
  def count_of_pull_requests_to_retarget_by_repo_id
    pull_requests_to_retarget.group(:head_repository_id).count
  end

  def human_error_reason
    case
    when failed_to_update_default_branch?,
         update_default_branch_dgit_error?,
         update_default_branch_gitrpc_timeout?,
         update_default_branch_exception?
      "could not change default branch of #{repository&.name_with_display_owner}"
    when pull_request_retarget_failed?
      "could not update pull request's base branch"
    when old_branch_dgit_error?,
         old_branch_hook_failure?,
         delete_old_branch_if_appropriate_exception?
      "could not delete branch #{old_name}"
    when old_branch_not_deletable?
      "branch #{old_name} cannot be deleted"
    when new_branch_invalid_name?
      "'#{new_name}' is not a valid branch name"
    when new_branch_dgit_error?,
         new_branch_hook_failure?
      "could not create branch #{new_name}"
    when new_branch_already_exists?
      "branch #{new_name} already exists"
    when unwritable_repository?,
         check_repository_writable_exception?
      "#{repository&.name_with_display_owner} is archived, migrating, or disabled"
    when start_rename_failed?
      "could not start renaming branch '#{old_name}' to '#{new_name}'"
    when create_protected_branch_exception?
      "branch protections do not permit creating branch '#{new_name}'"
    when finish_rename_failed?
      "could not finish renaming branch '#{old_name}' to '#{new_name}'"
    when repository_rule_violation?
      "repository rules do not permit renaming branch '#{old_name}' to '#{new_name}'"
    else
      error_reason
    end
  end

  def self.get_by_repo_and_old_name(repository_id:, old_name:)
    where(repository_id: repository_id, old_name: old_name)
  end

  private

  # Private: Get all the pull requests whose head branch or base branch is the branch being renamed.
  def affected_pull_requests
    return @affected_pull_requests if @affected_pull_requests
    pulls = PullRequest.open_based_on_ref(repository, old_name).to_repository(repository)

    if GitHub.spamminess_check_enabled?
      pr_head_repo_ids = pulls.pluck(:head_repository_id).uniq
      non_spammy_head_repo_ids = Repository.where(id: pr_head_repo_ids, user_hidden: false).pluck(:id)
      pulls = pulls.where(head_repository_id: non_spammy_head_repo_ids)
    end

    @affected_pull_requests = pulls
  end

  def set_default_branch
    if repository && old_name
      self.default_branch = repository&.default_branch == old_name
    end
  end

  def instrument_finished
    instrument :rename_branch
  end

  def instrument_errored
    GitHub.logger.info(
      "Renaming branch failed",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.branch_rename.old_sha" => old_sha,
      "gh.repo.branch_rename.old_branch" => old_name,
      "gh.repo.branch_rename.new_branch" => new_name,
      "gh.actor.id" => user&.id,
      "gh.repo.default_branch" => default_branch,
      "gh.repo.branch_rename.state" => state,
      "gh.repo.branch_rename.error_reason" => error_reason,
      "gh.repo.id" => repository&.id,
    )
  end

  delegate :event_prefix, to: :repository

  def event_payload
    payload = {
      event_prefix    => repository,
      :old_sha        => old_sha,
      :old_branch     => old_name,
      :new_branch     => new_name,
      :actor          => user,
      :default_branch => default_branch,
    }

    if owner = repository&.owner
      payload[owner.event_prefix] = owner
    end

    if org = repository&.organization
      payload[org.event_prefix] = org
    end

    payload
  end

  def ensure_names_differ
    return unless old_name && new_name
    return if errored?

    if old_name == new_name
      errors.add(:new_name, "cannot be the same as the current branch")
    end
  end

  def ensure_old_branch_exists
    return unless repository && old_name
    return unless started?

    ref = T.must(repository).heads.find(old_name)
    unless ref&.exist?
      errors.add(:old_name, "must exist")
    end
  end

  def ensure_new_branch_does_not_exist
    return unless repository && new_name
    return unless started?
    return if old_name == new_name

    ref = T.must(repository).heads.find(new_name)
    if ref&.exist?
      errors.add(:new_name, "already exists")
    end
  end

  def ensure_repo_writable
    return unless repository && started?

    unless repository&.writable?
      errors.add(:repository, "must not be archived, migrating, or disabled")
    end
  end

  # Private: Validates that there are no existing branch protection rules that
  # match the new branch name, because during the rename process, we attempt to
  # transfer rules from the old branch to the new branch, and that update will
  # fail if there's already an existing rule for the new branch name due to a
  # uniqueness validation on the protected branch name.
  #
  # Will only match rules that explicitly target the new branch name; wildcard
  # rules are intentionally ignored.
  def ensure_no_branch_protection_rules_for_new_name
    return unless repository && new_name
    if T.must(repository).protected_branches.where(name: new_name).exists?
      errors.add(:base, "delete the branch protection rule for \"#{new_name}\" and try again")
    end
  end

  def log_hydro_event
    return unless finished?

    GlobalInstrumenter.instrument "repository.rename_branch",
      repository: repository,
      actor: user,
      old_branch: old_name,
      new_branch: new_name,
      default_branch: default_branch
  end
end
