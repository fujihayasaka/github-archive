# typed: true
# frozen_string_literal: true

class AutoMergeRequest < ApplicationRecord::Domain::IssuesPullRequests
  class Invalid < StandardError ; end
  extend GitHub::Encoding

  force_utf8_encoding :commit_message, :commit_title

  belongs_to :pull_request
  belongs_to :user
  belongs_to :commit_email_address, class_name: "UserEmail"

  enum :merge_method, {
    auto_merge: 0,
    auto_squash_and_merge: 1,
    auto_rebase_and_merge: 2,
    merge_queue: 3,
    merge_queue_solo: 4,
    merge_queue_jump: 5
  }

  include GitHub::Validations

  validates :user, presence: true
  validates :pull_request, presence: true
  validates :merge_method, presence: true
  validates :commit_message, bytesize: { maximum: 65535 }, allow_blank: true
  validates :commit_title, bytesize: { maximum: 320 }, allow_blank: true

  validate :merge_method_is_allowed, on: :create
  validate :auto_merge_allowed, on: :create

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :create_enabled_issue_event, :instrument_enabled, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :publish_live_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :enqueue_auto_merge_check, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  VALID_DISABLE_REASON_CODES = [
    :base_changed_by_non_writer,
    :merge_queue,
    :closed,
    :converted_to_draft,
    :manually_disabled,
    :parent_mismatch,
    :push_from_non_writer,
    :rewrite,
    :workflow_policy_update_error
  ].concat(PullRequest::Merge::FailResult::VALID_FAIL_CODES)

  def self.enqueue!(pull_request:, merge_method:, user:, email: nil, commit_title: nil, commit_message: nil, remote_ip: nil)
    # attempt to enqueue immediately with merge queue. if that fails, use AutoMerge to enqueue for later
    merge_queue = MergeQueue.for(repository: pull_request.base_repository, branch: pull_request.base_ref)
    merge_method = full_merge_method!(has_merge_queue: merge_queue.present?, merge_method: merge_method&.to_sym)

    if merge_queue
      begin
        merge_queue
          .enqueue!(
            pull_request: pull_request,
            enqueuer: user,
            solo: merge_method == :merge_queue_solo,
            jump_queue: merge_method == :merge_queue_jump,
          )

        return true

      rescue ActiveRecord::RecordInvalid
        # fall through to AutoMergeRequest
      end
    end

    auto_merge_request = AutoMergeRequest.create!(
      pull_request: pull_request,
      user: user,
      merge_method: merge_method,
      commit_email_address: email,
      commit_title: commit_title,
      commit_message: commit_message,
      actor_ip_address: remote_ip
    )

    true
  rescue ActiveRecord::RecordNotUnique
    GitHub.logger.info(
      "duplicate AutoMergeRequest",
      "code.namespace" => "AutoMergeRequest",
      "code.function" => "enqueue!",
      "gh.pull_request.id" => pull_request.id
    )
  rescue ActiveRecord::RecordInvalid => e
    err = Invalid.new(e.record.errors.full_messages.to_sentence)
    raise err
  end

  # Override association method to ensure Bot users have their
  # IntegrationInstallation record set in memory, which is required for auth to
  # work correctly.
  def user
    super.tap do |found_user|
      if found_user.is_a?(Bot) && !found_user.installation && T.must(pull_request).repository
        # run for its side effect of setting found_user.installation
        found_user.async_load_installation_for(T.must(pull_request).repository).sync
      end
    end
  end

  def create_enabled_issue_event
    pull_request = T.must(self.pull_request)

    case merge_method
    when "auto_squash_and_merge"
      pull_request.events.create(event: "auto_squash_enabled", actor: user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when "auto_rebase_and_merge"
      pull_request.events.create(event: "auto_rebase_enabled", actor: user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      pull_request.events.create(event: "auto_merge_enabled", actor: user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    GlobalInstrumenter.instrument("pull_request.auto_merge_enable",
      {
        actor: user,
        repository: pull_request.repository,
        pull_request: pull_request,
        protected_branch: pull_request.base_branch_rule_evaluator&.original_protected_branch,
        unfulfilled_protected_branch_policy_reason_codes: unfulfilled_protected_branch_policy_reason_codes,
        auto_merge_request: self
      }
    )

    publish_live_update
  end

  def enqueue_auto_merge_check
    T.must(pull_request).enqueue_auto_merge_job_if_enabled
  end

  def instrument_enabled
    T.must(pull_request).instrument(:auto_merge_enabled, actor: user)
  end

  # Disable auto-merge for the associated pull request
  #
  # reason_code - Reason for auto-merge being disabled. This affects what is displayed
  #               on the associated issue event and must be from the predefined list of
  #               VALID_DISABLE_REASON_CODES. An actor is required for :manually_disabled
  #               disabled by a user.
  #
  # actor       - User who is disabling auto-merge. Required with reason_code :manually_disabled
  def disable(reason_code, actor: nil)
    pull_request = T.must(self.pull_request)

    unless VALID_DISABLE_REASON_CODES.include?(reason_code)
      err = Invalid.new("Invalid reason_code")
      Failbot.report(err, "gh.pull_request.reason_code": reason_code)
      raise err
    end

    if reason_code == :manually_disabled && actor.nil?
      err = Invalid.new("an actor is required with reason_code: 'manually_disabled'")
      Failbot.report(err, "gh.pull_request.reason_code": reason_code)
      raise err
    end

    pull_request.create_issue_event(
      :auto_merge_disabled,
      actor || user,
      message: reason_code
    )

    publish_live_update

    unfulfilled_reason_codes = unfulfilled_protected_branch_policy_reason_codes(actor)

    GlobalInstrumenter.instrument("pull_request.auto_merge_disable",
      {
        actor: actor,
        repository: pull_request.repository,
        pull_request: pull_request,
        disabled_message: reason_code,
        protected_branch: pull_request.base_branch_rule_evaluator&.original_protected_branch,
        unfulfilled_protected_branch_policy_reason_codes: unfulfilled_reason_codes,
        auto_merge_request: self
      }
    )

    # We most likely should have auto merged this PR - track how often this is happening.
    if unfulfilled_reason_codes.length == 0
      GitHub.dogstats.increment "pull_request.auto_merge_disabled_with_no_reasons"
    end

    pull_request.instrument(:auto_merge_disabled, actor: actor || user, reason: self.class.reason_message(reason_code))

    destroy
  end

  def unfulfilled_protected_branch_policy_reason_codes(actor = nil)
    actor ||= user
    @unfulfilled_codes ||= {}

    @unfulfilled_codes[actor&.id] ||= T.must(pull_request).merge_state(viewer: actor).unfulfilled_protected_branch_policy_reason_codes
  end

  def async_repository
    async_pull_request.then do |pull_request|
      T.must(pull_request).async_repository
    end
  end

  def publish_live_update
    pull_request&.notify_socket_subscribers
    channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
    GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
  end

  def merge_method_is_allowed
    return unless (pull_request = self.pull_request).present?

    if merge_method == "auto_merge" && !pull_request.merge_commit_allowed?(actor: user)
      errors.add(:merge_method, "merge commits are not allowed on this repository")
    elsif merge_method == "auto_squash_and_merge" && !pull_request.squash_merge_allowed?(actor: user)
      errors.add(:merge_method, "squash merging is not allowed on this repository")
    elsif merge_method == "auto_rebase_and_merge" && !pull_request.rebase_merge_allowed?(actor: user)
      errors.add(:merge_method, "rebase merging is not allowed on this repository")
    end
  end

  def auto_merge_allowed
    return unless (pull_request = self.pull_request).present?
    result = pull_request.can_enable_auto_merge(actor: user)
    unless result.allowed?
      errors.add(:pull_request, result.reason)
    end
  end

  def minimal_merge_method
    async_pull_request.then do |pull_request|
      T.must(pull_request).async_merge_queue.then do |merge_queue|
        if merge_queue
          merge_queue.merge_method.to_sym
        elsif merge_method == "auto_merge"
          :merge
        elsif merge_method == "auto_rebase_and_merge"
          :rebase
        elsif merge_method == "auto_squash_and_merge"
          :squash
        elsif merge_method == "merge_queue_solo"
          :merge
        elsif merge_method == "merge_queue_jump"
          :merge
        else
          :merge
        end
      end
    end.sync
  end

  # Get a human readable message from given reason_code symbol
  def self.reason_message(reason_code)
    raise ArgumentError.new(
      "reason_code must be a symbol"
    ) unless reason_code.class == Symbol

    raise ArgumentError.new(
      "Invalid reason_code: #{reason_code}"
    ) unless VALID_DISABLE_REASON_CODES.include?(reason_code)

    case reason_code
    when :manually_disabled
      "Manually disabled by user"
    when :base_missing
      "Base branch no longer exists"
    when :closed
      "Pull request was closed"
    when :converted_to_draft
      "Pull request was converted to draft"
    when :push_from_non_writer
      "Head branch was pushed to by a user without write access"
    when :base_changed_by_non_writer
      "Base branch changed by a user without write access"
    when :denied
      "Merge could not be authorized"
    when :draft
      "Pull request is a draft"
    when :head_mismatch
      "Head branch was modified"
    when :invalid_email
      "Invalid email address"
    when :merge_commit_blocked
      "Merge commits are not allowed on this repository"
    when :not_mergeable
      "Pull Request is not mergeable"
    when :parent_mismatch
      "Base branch was modified"
    when :protected_branch
      "Base branch requires signed commits"
    when :rebase
      "Rebase failed"
    when :rebase_merge_blocked
      "Rebase merges are not allowed on this repository"
    when :rewrite
      "Could not re-write the merge commit for some reason"
    when :squash_merge_blocked
      "Squash merges are not allowed on this repository"
    when :merge_queue
      "Merge queue setting changed"
    when :workflow_policy_update_error
      "Tried to create or update workflow without `workflows` permission"
    when :repository_rule_violation
      "Repository rule violations found"
    end
  end

  # inverse of minimal_merge_method
  # kind of wish I didn't have to do this but the public apis
  # specify the the minimal merge method names while the database has records
  # with the longer version.
  private_class_method def self.full_merge_method!(has_merge_queue:, merge_method:)
    if has_merge_queue
      return :merge_queue_solo if merge_method == :solo
      return :merge_queue_jump if merge_method == :jump
      return :merge_queue
    end

    return :auto_squash_and_merge if merge_method == :squash
    return :auto_rebase_and_merge if merge_method == :rebase
    :auto_merge
  end

  private

  def set_repository_id
    self.repository_id = self.pull_request&.repository_id
  end
end
