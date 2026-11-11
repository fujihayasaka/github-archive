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
    merge_queue_jump: 5,
    merge_queue_stack: 6,
    auto_merge_stack: 7,
  }

  include GitHub::Validations

  # Used to skip callbacks on :create to bypass validations
  # to support backing inline merging with auto merge
  # Otherwise, it will fail because the PR is in a "clean" state
  attr_accessor :skip_create_callbacks
  alias_method :skip_create_callbacks?, :skip_create_callbacks

  # Set by the auto_merge_allowed validation so callers can inspect the
  # rejection category if needed (e.g. for metrics)
  attr_accessor :last_rejection_category

  # These are used in the Creator but not yet in the DB schema
  attr_accessor :mode, :mode_configuration

  validates :user, presence: true
  validates :pull_request, presence: true
  validates :merge_method, presence: true
  validates :commit_message, bytesize: { maximum: 65535 }, allow_blank: true
  validates :commit_title, bytesize: { maximum: 320 }, allow_blank: true

  validate :merge_method_is_allowed, on: :create, unless: :skip_create_callbacks?
  validate :auto_merge_allowed, on: :create, unless: :skip_create_callbacks?

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :create_enabled_issue_event, :instrument_enabled, on: :create, unless: :skip_create_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :publish_live_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :enqueue_auto_merge_check, on: :create, unless: :skip_create_callbacks?  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :enqueue_auto_merge_check, on: :update  # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  VALID_DISABLE_REASON_CODES = [
    :base_changed_by_non_writer,
    :merge_queue,
    :closed,
    :converted_to_draft,
    :manually_disabled,
    :parent_mismatch,
    :push_from_non_writer,
    :rewrite,
    :workflow_policy_update_error,
    :pull_request_unstacked,
  ].concat(PullRequest::Merge::FailResult::VALID_FAIL_CODES)

  def self.enqueue!(pull_request:, merge_method:, user:, email: nil, commit_title: nil, commit_message: nil, remote_ip: nil)
    logger = nil
    terminal_state_logging_enabled = false
    original_merge_method = merge_method
    begin
      logger = PullRequests::Shared::Logger.new(
        default_prefix: "gh.pull_request.auto_merge_request",
        feature: "auto_merge"
      )
      logger.append_pull_request_context(pull_request)
      logger.append({
        phase: "enqueue",
        merge_method: merge_method,
        user_id: user&.id,
        email: email.to_s,
        commit_title: commit_title,
        commit_message: commit_message,
        remote_ip: remote_ip,
      })
      terminal_state_logging_enabled = FeatureFlag.vexi.enabled?(:auto_merge_telemetry, pull_request&.repository, default: false)

      merge_method = merge_method&.to_sym

      # Handle stacked PR merge queue enqueue
      case merge_method
      when :auto_merge_stack, :merge_queue_stack
        case result = PullRequests::Stacks::Enqueue.call(
          pull_request:, email:, commit_title:, commit_message:, remote_ip:,
          actor: user,
        )
        when PullRequests::Stacks::Merging::Result::Success
          return true
        when PullRequests::Stacks::Merging::Result::NoLongerStacked
          raise Invalid, "Pull request is not part of a stack"
        when PullRequests::Stacks::Merging::Result::Error
          raise Invalid, result.message
        end
      end

      # attempt to enqueue immediately with merge queue. if that fails, use AutoMerge to enqueue for later
      merge_queue = MergeQueue.for(repository: pull_request.base_repository, branch: pull_request.base_ref)
      merge_method = full_merge_method!(has_merge_queue: merge_queue.present?, merge_method: merge_method)

      if merge_queue
        begin
          merge_queue
            .enqueue!(
              pull_request: pull_request,
              enqueuer: user,
              solo: merge_method == :merge_queue_solo,
              jump_queue: merge_method == :merge_queue_jump,
            )

          if FeatureFlag.vexi.enabled?(:am_mutations_logging, pull_request&.repository, default: false)
            GitHub.logger.info("gh.pull_requests.auto_merge_request.enqueue.direct_queue_success",
              pull_request_id: pull_request.id,
              merge_queue_id: merge_queue.id
            )
          end

          logger.append({
            merge_queue_id: merge_queue.id,
            # logging the merge method used to attempt to enqueue a merge queue entry
            merge_method: merge_method,
            outcome: "direct_merge_queue_success",
          })

          return true

        rescue ActiveRecord::RecordInvalid => e
          # fall through to AutoMergeRequest
          if !terminal_state_logging_enabled
            GitHub.logger.info("gh.pull_requests.auto_merge_request.enqueue.direct_queue_failed",
              pull_request_id: pull_request.id,
              merge_queue_id: merge_queue.id,
              validation_errors: e.record.errors.full_messages.join(", ")
            )
          else
            logger.append({
              merge_queue_id: merge_queue.id,
              # logging the merge method used to attempt to enqueue a merge queue entry
              merge_method: merge_method,
              outcome: "direct_merge_queue_failed",
            })
          end
        ensure
          logger.flush if terminal_state_logging_enabled
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

      if FeatureFlag.vexi.enabled?(:am_mutations_logging, pull_request&.repository, default: false) && !terminal_state_logging_enabled
        GitHub.logger.info("gh.pull_requests.auto_merge_request.enqueue.created_waiting_request",
          pull_request_id: pull_request.id,
          auto_merge_request_id: auto_merge_request.id,
          merge_method: merge_method
        )
      end

      logger.append({
        id: auto_merge_request.id,
        merge_method: original_merge_method,
        outcome: "created_waiting_request",
      })

      true
    rescue ActiveRecord::RecordNotUnique => e
      GitHub.logger.info(
        "duplicate AutoMergeRequest",
        "code.namespace" => "AutoMergeRequest",
        "code.function" => "enqueue!",
        "gh.pull_request.id" => pull_request.id
      ) unless terminal_state_logging_enabled

      logger&.append({
        outcome: "duplicate",
        validation_errors: "record_not_unique",
      })
      logger&.append_exception(e, prefix: "gh.pull_request.auto_merge_request")
    rescue ActiveRecord::RecordInvalid => e
      err = Invalid.new(e.record.errors.full_messages.to_sentence)

      logger&.append({
        outcome: "error_validation_failed",
        validation_errors: e.record.errors.full_messages.join(", "),
        rejection_category: e.record.try(:last_rejection_category)&.to_s,
      })
      logger&.append_exception(e, prefix: "gh.pull_request.auto_merge_request")

      raise err
    ensure
      logger.flush if terminal_state_logging_enabled
    end
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

    ActiveRecord::Base.connected_to(role: :writing) { destroy }
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
    return if merge_method&.start_with?("merge_queue_") || merge_method == "auto_merge_stack"

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
      self.last_rejection_category = result.rejection_category
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
        elsif merge_method == "merge_queue_stack"
          :merge
        elsif merge_method == "auto_merge_stack"
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
    when :pull_request_unstacked
      "Pull request removed from stack"
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
