# typed: true
# frozen_string_literal: true

class RepositoryClone < ApplicationRecord::Collab
  belongs_to :template_repository, class_name: "Repository"
  delete_in_background_with :template_repository
  belongs_to :clone_repository, class_name: "Repository"
  belongs_to :cloning_user, class_name: "User"

  MAX_REPO_DISK_USAGE_IN_KILOBYTES = 1_000_000
  MAX_TEMPLATE_FILE_LIMIT = 100_000

  enum :error_reason_code, [
    :missing_template_repo,
    :missing_clone_repo,
    :no_commit_oid,
    :failed_to_update_branch,
    :repo_size_too_large,
    :git_object_missing,
    :git_timeout,
    :cannot_finish,
    :dgit_exception,
    :gitrpc_exception,
    :rule_violations,
    :other_exception,
  ]

  enum :state, {
    cloning: 0,
    finished: 1,
    error: 2,
  }

  validates :template_repository, :clone_repository, :cloning_user, :state, presence: true
  validates :clone_repository_id, uniqueness: true
  validate :template_repository_is_template
  validate :template_repository_is_active
  validate :cloning_user_has_access_to_clone_repository

  scope :for_clone_repo, ->(repo) { where(clone_repository_id: repo) }
  scope :cloning, -> { where(state: states[:cloning]) }
  scope :finished, -> { where(state: states[:finished]) }
  scope :for_user, ->(user) { where(cloning_user_id: user) }

  after_create :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks


  def template_owner
    template_repository&.owner
  end

  private

  def instrument_create
    payload = {
      user: cloning_user,
      clone_repository: clone_repository,
      template_repository: template_repository,
    }
    GlobalInstrumenter.instrument("repository_clone.created", payload)
  end

  def template_repository_is_template
    return unless template_repository

    unless template_repository&.template?
      errors.add(:template_repository, "must be marked as a template")
    end
  end

  def template_repository_is_active
    return unless template_repository

    unless template_repository&.active?
      errors.add(:template_repository, "must be active")
    end
  end

  def cloning_user_has_access_to_clone_repository
    return unless cloning_user && clone_repository

    if cloning_user&.bot? && !T.cast(cloning_user, Bot).installation
      installations = T.cast(cloning_user, Bot).integration&.installations
      T.cast(cloning_user, Bot).installation = T.unsafe(installations).with_repository(clone_repository).first
    end

    unless clone_repository&.resources.contents.readable_by?(cloning_user)
      errors.add(:cloning_user, "does not have permission to view the clone repository")
    end
  end
end
