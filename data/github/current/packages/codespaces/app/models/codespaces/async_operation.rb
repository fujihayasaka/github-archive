# typed: true
# frozen_string_literal: true

module Codespaces
  class AsyncOperation < ApplicationRecord::Domain::Codespaces
    include GitHub::Memoizer

    class PendingError < ::Codespaces::Error; end
    class OperationTypeError < ::Codespaces::Error; end

    OperationConfig = Struct.new(
      :operation,
      :completion_criteria,
      :completion_state,
      :on_completion,
      :start_timeout,
      :finish_timeout,
      :display_text,
      :disabled_text,
      :reverify_after,
      :blocking,
      keyword_init: true,
    )

    class State
      REQUESTED = "requested"
      STARTED = "started"
      ENDED = "ended"
      SUCCEEDED = "succeeded"
      FAILED = "failed"
    end

    OPERATION_CONFIG = ActiveSupport::HashWithIndifferentAccess.new({
      update_storage: OperationConfig.new(
        operation: :update_storage,
        blocking: true,
        completion_criteria: [
          -> (_codespace, env) {
            env.state == Codespaces::Vscs::State::SHUTDOWN
          },
        ],
        on_completion: -> (codespace, env) {
          if codespace.sku_name != env.sku_name
            codespace.update!(sku_name: env.sku_name)
          end
        },
        reverify_after: 10.minutes,
        start_timeout: 5.minutes,
        display_text: "updating to a sku with a different amount of storage",
        disabled_text: "Changing machine types...",
        # don't do anything if we haven't been told by VSCS that the state has
        # changed. This codespace will either receive a state update/webhook or
        # get tossed back to this job the next time it runs.
      ),
      create_codespace: OperationConfig.new(
        operation: :create_codespace,
        blocking: false,
        completion_criteria: [
          -> (_codespace, env) {
            env.state == Codespaces::Vscs::State::AVAILABLE
          },
          -> (_codespace, env) {
            env.state == Codespaces::Vscs::State::FAILED
          },
        ],
        completion_state: -> (env) {
          if env.state == Codespaces::Vscs::State::AVAILABLE
            State::SUCCEEDED
          else
            State::FAILED
          end
        },
        finish_timeout: 90.minutes,
        reverify_after: 10.minutes,
        start_timeout: (2 * GitHub.default_request_timeout).seconds,
        display_text: "creating codespace",
        disabled_text: "Creating codespace..."
      ),
      start_codespace: OperationConfig.new(
        operation: :start_codespace,
        blocking: false,
        completion_criteria: [
          -> (_codespace, env) {
            env.state == Codespaces::Vscs::State::AVAILABLE
          },
          -> (_codespace, env) {
            env.state == Codespaces::Vscs::State::SHUTDOWN
          },
        ],
        completion_state: -> (env) {
          if env.state == Codespaces::Vscs::State::AVAILABLE
            State::SUCCEEDED
          else
            State::FAILED
          end
        },
        finish_timeout: 90.minutes,
        reverify_after: 5.minutes,
        start_timeout: 5.minutes, # Start can be shoved to the background so using the request timeout is inappropriate
        display_text: "starting codespace",
        disabled_text: "Starting codespace...",
      ),

      # TODO: eventually we need to move export over to using this mechanism
      # https://github.com/github/codespaces/issues/6471
      # export: OperationConfig.new(
      #   completion_criteria: [
      #     -> (codespace, env) {
      #       return false
      #     },
      #   ],
      #   on_completion: -> (_, _) { },
      #   finish_timeout: 5.minutes,
      #   start_timeout: 5.minutes,
      #   display_text: "exporting the contents of the codespace to a branch",
      #   disabled_text: "Exporting to a branch..."
      # )
    })

    self.table_name = "codespace_async_operations"

    belongs_to :codespace

    def codespace
      Codespace.unscoped { super }
    end

    scope :pending, -> { where(op_ended_at: nil) }
    scope :completed, -> { where.not(op_ended_at: nil) }
    scope :blocking, -> { where(operation: blocking_operations.map(&:operation)) }

    enum :operation, [
      :update_storage,
      :create_codespace,
      :start_codespace,
      # :export, # See above TODO
    ]

    after_create :report_operation

    attr_accessor :user, :vscs_target

    def self.blocking_operations
      OPERATION_CONFIG.values.select(&:blocking)
    end

    def self.non_blocking_operations
      OPERATION_CONFIG.values - blocking_operations
    end

    def self.check_for_completed_operations(codespace, env: codespace.environment_data)
      codespace.pending_async_operations.where.not(op_started_at: nil).each do |op|
        op.check_for_completed_state(codespace, env)
      end
    end

    def self.report_complete(operation:, completion_state:, codespaces_automated_testing: false, failure_reason: nil, caller: nil)
      tags = ["operation:#{operation}", "state:#{completion_state}", "failsafe_reporting:true"]
      if codespaces_automated_testing
        tags << "codespaces_automated_testing:true"
      end
      GitHub.dogstats.increment("codespaces.async_operations.ended", tags:)
      if GitHub.flipper[:codespaces_failsafe_report_splunk].enabled?
        GitHub.logger.info(
          "codespaces async operation changed state",
          {
            "gh.codespaces.async_operation.name" => operation.to_s,
            "gh.codespaces.automated_testing" => codespaces_automated_testing,
            "gh.codespaces.async_operation.state" => completion_state,
            "gh.codespaces.async_operation.failure_reason" => failure_reason,
            "gh.codespaces.async_operation.caller" => caller,
            "gh.request_id" => GitHub.context[:request_id],
          }
        )
      end
    end

    def self.report_failure(operation:, codespaces_automated_testing: false, failure_reason: nil)
      caller = nil
      if failure_reason && GitHub.flipper[:codespaces_failsafe_report_splunk].enabled?
        caller = T.must(caller_locations[0]).to_s
        if failure_reason.kind_of?(Exception)
          failure_reason = failure_reason.class.to_s
        end
      end
      report_complete(operation:, completion_state: State::FAILED, codespaces_automated_testing:, failure_reason:, caller:)
    end

    def self.report_ended(operation:, codespaces_automated_testing: false)
      report_complete(operation:, completion_state: State::ENDED, codespaces_automated_testing:)
    end

    def self.unstarted_operations

      unstarted_ops_query_fragments = OPERATION_CONFIG.map do |op, config|
        where(
          op_started_at: nil,
          op_ended_at: nil,
          created_at: ..config.start_timeout.ago,
          operation: op,
        )
      end

      unstarted_ops_query_fragments.reduce(&:or)
    end

    def self.ongoing_operations
      pollable_operation_types = OPERATION_CONFIG.select do |_, config|
        config.reverify_after.present?
      end
      ongoing_ops_query_fragments = pollable_operation_types.map do |op, config|
        where.not(op_started_at: nil)
          .and(where(
            op_started_at: ..config.reverify_after.ago,
            operation: op, op_ended_at: nil,
          ))
      end

      ongoing_ops_query_fragments.reduce(&:or)
    end

    def self.hung_operations
      timeoutable_operation_types = OPERATION_CONFIG.select do |_, config|
        config.finish_timeout.present?
      end
      unfinished_ops_query_fragments = timeoutable_operation_types.map do |op, config|
        where.not(op_started_at: nil)
          .and(where(
            op_started_at: ..config.finish_timeout.ago,
            operation: op, op_ended_at: nil,
          ))
      end

      unfinished_ops_query_fragments.reduce(&:or)
    end

    def ensure_operation_type(operation_type)
      raise OperationTypeError.new("expected #{operation_type} got #{operation}") unless operation.to_sym == operation_type.to_sym
    end

    def started?
      op_started_at.present?
    end

    def ended?
      op_ended_at.present?
    end

    def mark_as_started
      return if started? || ended?
      ActiveRecord::Base.connected_to(role: :writing) do
        touch(:op_started_at)
      end
      report_operation
    end

    def mark_as_ended(completion_state: State::ENDED, failure_reason: nil, caller: nil)
      return if ended?
      ActiveRecord::Base.connected_to(role: :writing) do
        touch(:op_ended_at)
      end
      report_operation(completion_state:, failure_reason:, caller:)
    end

    def mark_as_failed(failure_reason: nil)
      caller = nil
      if failure_reason
        caller = T.must(caller_locations[0]).to_s
        if failure_reason.kind_of?(Exception)
          failure_reason = failure_reason.class.to_s
        end
      end
      mark_as_ended(completion_state: State::FAILED, failure_reason:, caller:)
    end

    def mark_as_succeeded
      mark_as_ended(completion_state: State::SUCCEEDED)
    end

    def self.ensure_no_blocking_pending!(codespace)
      blocking_types = blocking_operations.map(&:operation)

      op = self.pending.where(operation: blocking_types).find_by(codespace: codespace)
      return unless op
      raise PendingError.new(
        "your codespace has an operation pending: #{op.display_text}; please wait until this operation is complete"
      )
    end

    def check_if_complete(force_update: false)
      return false unless codespace

      if force_update
        # if we were asked to force an update by fetching the environment we need a codespace with a guid or we can't check.
        return false unless codespace.guid.present?
        # We also shouldn't check if the owner has been deleted because the client will raise an ArgumentError
        return false unless codespace.owner.present?

        # calls fetch environment and then sets it on the codespace
        begin
          client.fetch_environment!(codespace.guid, include_deleted: codespace.deleted?)
          codespace.reload
        rescue Codespaces::VscsClient::BadResponseError
          return false
        end
      end

      env = codespace.environment_data
      check_for_completed_state(codespace, env)
    end

    def check_for_completed_state(codespace, env)
      return false if !started?
      return false if env.updated <= op_started_at
      completion_criteria.any? do |criteria|
        if criteria.call(codespace, env)
          state = if completion_state.respond_to?(:call)
            completion_state.call(env)
          else
            State::ENDED
          end
          mark_as_ended(completion_state: state)
          on_completion.respond_to?(:call) && on_completion.call(codespace, env)
          true
        end
      end
    end

    def display_text
      operation_config.display_text || "unknown pending operation"
    end

    def disabled_text
      operation_config.disabled_text || "Pending operation..."
    end

    def start_timed_out?
      return false if started?

      timeout = start_timeout || 10.minutes

      if created_at.nil?
        false
      else
        T.must(created_at) < timeout.ago
      end
    end

    def finish_timed_out?
      return false if ended?

      return false unless finish_timeout

      if !started?
        false
      else
        T.must(op_started_at) < finish_timeout.ago
      end
    end

    delegate :completion_criteria, :completion_state, :on_completion, :start_timeout, :finish_timeout, :reverify_after, to: :operation_config, allow_nil: true

    private

    memoize def operation_config
      OPERATION_CONFIG[operation]
    end

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end

    def report_operation(completion_state: nil, failure_reason: nil, caller: nil)
      ld = {}

      if ended?
        ended_tags = dd_tags(completion_state:)
        if failure_reason.present?
          ended_tags << "failure_reason:#{failure_reason}"
          ld[:failure_reason] = failure_reason
          ld[:caller] = caller
        end
        if started?
          ld[:start_to_end_seconds] = T.must(op_ended_at) - op_started_at
          ld[:request_to_start_seconds] = T.must(op_started_at) - created_at
        end
        ld[:request_to_end_seconds] = T.must(op_ended_at) - created_at
        GitHub.dogstats.distribution("codespaces.async_operations.request_to_end_seconds", ld[:request_to_end_seconds], tags: (ended_tags || []) + codespace_timing_tags)
        if ld[:start_to_end_seconds].present?
          GitHub.dogstats.distribution("codespaces.async_operations.start_to_end_seconds", ld[:start_to_end_seconds], tags: ended_tags)
        end
        GitHub.dogstats.increment("codespaces.async_operations.ended", tags: ended_tags)
      elsif self.op_started_at.present?
        ld[:request_to_start_seconds] = T.must(op_started_at) - created_at
        GitHub.dogstats.distribution("codespaces.async_operations.request_to_start_seconds", ld[:request_to_start_seconds], tags: dd_tags)
      else
        GitHub.dogstats.increment("codespaces.async_operations.requested", tags: dd_tags)
      end

      GitHub.logger.info(
        "codespaces async operation changed state",
        {
          "gh.codespaces.async_operation.id" => id,
          "gh.codespaces.async_operation.name" => operation,
          "gh.codespaces.async_operation.state" => tags(completion_state:)[:state],
          "gh.codespaces.name" => codespace&.name,
          "gh.codespaces.automated_testing" => !!stats_tagger&.all_tags&.dig(:codespaces_automated_testing),
          "gh.request_id" => GitHub.context[:request_id],
        }.merge(
          ld.transform_keys { |k| "gh.codespaces.async_operation.#{k}" }
        ),
      )
    end

    def dd_tags(completion_state: nil)
      codespace_dd_tags + tags(completion_state:).map do |k, v|
        "#{k}:#{v}"
      end
    end

    def codespace_dd_tags
      tags = stats_tagger&.datadog_tags || ["codespace_unavailable:true"]

      if codespaces_add_tags_to_async_operation?
        tags << "repo_id:#{codespace.repository.id}"
      end

      tags
    end

    def codespace_timing_tags
      tags = []
      return tags unless codespaces_add_tags_to_async_operation?

      prebuild_type = codespace.environment_data&.prebuild_type
      tags << "prebuild_type:#{prebuild_type}" if prebuild_type.present?

      is_allocated_from_pool = codespace.environment_data&.is_allocated_from_pool
      tags << "is_allocated_from_pool:#{is_allocated_from_pool}" if is_allocated_from_pool.present?

      create_from_prebuild = codespace.environment_data&.create_from_prebuild
      tags << "create_from_prebuild:#{create_from_prebuild}" if create_from_prebuild.present?

      tags
    end

    def codespaces_add_tags_to_async_operation?
      codespace&.repository&.feature_enabled?(:codespaces_tag_repo_in_async_operation)
    end

    def stats_tagger
      if codespace.present?
        StatsTagger.new(codespace:)
      elsif user.present?
        StatsTagger.new(owner: user, vscs_target: vscs_target)
      end
    end

    def tags(completion_state: nil)
      t = {
        operation: operation,
      }

      t[:state] = if completion_state.present?
        completion_state.to_s
      elsif ended?
        State::ENDED
      elsif started?
        State::STARTED
      else
        State::REQUESTED
      end

      t
    end

  end
end
