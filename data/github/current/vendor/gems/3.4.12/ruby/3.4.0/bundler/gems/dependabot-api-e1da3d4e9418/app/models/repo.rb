# frozen_string_literal: true

require "nullable_serializer"

class Repo < ApplicationRecord
  include FlipperActor

  belongs_to :account

  has_many :pull_requests
  has_many :update_configs
  has_many :multi_ecosystem_configs, -> { distinct }, through: :update_configs
  has_many :update_jobs, through: :update_configs
  has_many :registries, as: :source
  has_many :active_update_configs, -> { active },
           class_name: "UpdateConfig",
           inverse_of: :repo
  has_one :config_file_error

  validates :account, presence: true
  validates :github_id, presence: true
  validates :name, presence: true
  validates :default_branch, presence: true
  validates :private, inclusion: { in: [true, false] }
  validates :unreliable_test_suite, inclusion: { in: [true, false] }
  validates :has_ci, inclusion: { in: [true, false] }

  after_update_commit :update_pr_base_branches, if: :default_branch_changed?
  after_update_commit :enqueue_config_file_check, if: :default_branch_changed?

  scope :active, -> { joins(:update_configs).merge(UpdateConfig.active) }

  # Prevents a client from asking for an excessively large
  # number of update configs in a single request.
  MAXIMUM_CONFIGS_ALLOWED = 200

  PAUSED_LABEL = "dependabot-paused"

  def paused?
    paused_at.present?
  end

  def recently_inactive?
    will_pause_at?
  end

  def should_be_paused?
    will_pause_at && will_pause_at < Time.current
  end

  def pause!(event_source:)
    return true if paused?

    PauseRepoJob.perform_later(repo_id: id, event_source: event_source)
    true
  end

  def full_name
    raise unless account

    account.github_login + "/" + name
  end
  alias nwo full_name

  def github_url
    "#{Prius.get(:target_github_url)}#{full_name}"
  end

  def using_config_file?
    config_file_path.present?
  end

  def flipper_id
    "Repo:#{id}"
  end

  def active?
    active_update_configs.any?
  end

  def automerge_enabled?
    # This change makes the automerge_enabled? method more robust by ensuring
    # it always returns true or false, rather than nil.
    # Context: In the GHES 3.14 environment, automerge_enabled was set to nil,
    # causing automerge_enabled? to return nil, which led to a TypeError because
    # it should return a boolean value.
    # Issue: https://github.com/github/dependabot-updates/issues/6308#issuecomment-2195598144
    !!automerge_enabled && feature_enabled?(:automerge)
  end

  # Test our local feature flag implementation
  def config_feature_enabled?(feature)
    feature_enabled?(feature) ||
      account.feature_enabled?(feature)
  end

  # Check if the org-level feature flag is enabled for the given org
  def org_level_flag_enabled?(feature)
    account.feature_enabled?(feature)
  end

  # Check if the repo-level feature flag is enabled for the given repo
  def repo_level_flag_enabled?(feature)
    feature_enabled?(feature)
  end

  def settings
    @settings ||= RepositorySettings.new(self)
  end

  def default_update_schedule_time_of_day
    # break the day into 10 minute slots:
    slot = Random.new(id).rand(24 * 6)
    hour = (slot / 6) % 24
    minute = (slot % 6) * 10
    format("%<hh>02d:%<mm>02d", hh: hour, mm: minute)
  end

  def event_stream
    @event_stream ||= Activity::RepositoryLogger.new(repo: self)
  end

  def audit_log_message(action) # rubocop:disable Metrics/MethodLength
    paused_at_time = Time.now.utc.to_i
    document_id = SecureRandom.urlsafe_base64(16)
    document = {
      action: action,
      actor: Dependabot::Application.integration_login,
      actor_id: Dependabot::Application.github_dependabot_user_id,
      repo: name,
      repo_id: id,
      '@timestamp': paused_at_time,
      _document_id: document_id,
    }

    if account.account_type == "user"
      document[:user_id] = account.github_id
      document[:user] = account.github_login
    else
      document[:org_id] = account.github_id
      document[:org] = account.github_login
    end

    {
      action: action,
      document: document.to_json,
      document_id: document_id,
      event_time: paused_at_time,
      audit_log: :GITHUB,
    }
  end

  def autofix_enabled?
    monolith_feature_enabled?(:dependabot_autofix, use_cache: true)
  end

  # Test the monolith's feature flags
  def monolith_feature_enabled?(feature_flag, use_cache: true)
    Dependabot::Application.monolith_feature_enabled?(
      feature: feature_flag,
      actor: self,
      use_cache: use_cache
    )
  end

  # Translates this actor into a monolith object within
  # Dependabot::Application.monolith_feature_enabled?
  def monolith_actor
    @monolith_actor ||= FeatureFlags::Actor::Repository.new(github_id)
  end

  def telemetry_attributes
    {
      "gh.repo.id": github_id,
      "gh.owner.id": account.github_id,
      "gh.repo.visibility": visibility,
    }
  end

  private

  def default_branch_changed?
    saved_change_to_default_branch?
  end

  def visibility
    if private?
      "private"
    else
      "public"
    end
  end

  # TODO: Extract to background job
  #
  # This query running in an after_commit hook could pose problems as our
  # database grows.
  def update_pr_base_branches
    return unless account.active?
    return if paused?

    pull_requests.open.
      joins(:update_config).
      merge(UpdateConfig.active).
      where(update_configs: { target_branch: nil }).
      find_each do |pr|
        UpdatePullRequestBaseBranchJob.perform_later(pull_request: pr)
      end
  end

  def enqueue_config_file_check
    return unless account.active?

    ResyncRepoConfigFileJob.perform_later(
      account: account,
      repo_name: name,
      repo_github_id: github_id,
    )
  end
end
