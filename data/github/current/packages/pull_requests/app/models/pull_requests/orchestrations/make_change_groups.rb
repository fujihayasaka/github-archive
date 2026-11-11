# typed: true
# frozen_string_literal: true

module PullRequests
  module Orchestrations
    class MakeChangeGroups < PullRequestOrchestration
      include DataAttributes

      observability_feature_name :make_change_groups

      class FailureReason < T::Enum
        enums do
          Unknown = new(:unknown)

          CopilotError = new(:capi_error)
          DiffTooLarge = new(:diff_too_large)
          DiffTooSmall = new(:diff_too_small)
          InvalidGroups = new(:invalid_groups)
          PromptTooLong = new(:prompt_too_long)
          PullRequestNotFound = new(:pull_request_not_found)
          CompareRepositoryNotFound = new(:compare_repository_not_found)
          TooFewGroups = new(:too_few_groups)
          TooManyGroups = new(:too_many_groups)
          UnknownHunkIDs = new(:unknown_hunk_ids)
        end

        def self.deserialize(value)
          super
        rescue KeyError
          Unknown
        end
      end

      on_end_orchestration do |_error_message, _error_class|
        notify_pull_request_alive_channel
        GlobalInstrumenter.instrument("pull_request_change_groups.generated",
          pull_request:,
          orchestration: self,
          change_groups:,
        )
      end

      MIN_DIFF_HUNKS = 2
      REFERENCED_ISSUE_LIMIT = 3

      MIN_GROUPS = 2
      MAX_GROUPS = 10

      # A P99 value for prompt length.
      # CAPI request will fail if prompt is longer than 64_000 tokens
      MAX_PROMPT_LENGTH = 256_000 # ~64,000 tokens

      data :actor, User, required: true, persisted: true
      data :head_commit_oid, String, required: false, persisted: true
      data :base_commit_oid, String, required: false, persisted: true
      data :failure_reason, FailureReason, required: false, persisted: true,
        custom_serializer: {
          to_db: ->(value) { value&.serialize },
          from_db: ->(symbol) { FailureReason.deserialize(symbol) unless symbol.nil? },
        }
      data :make_change_groups_attempts, Integer, required: false, persisted: true, default: 0

      sig { returns(T.nilable(GitHub::Diff)) }
      attr_accessor :diff

      sig { returns(T.nilable(T::Hash[Integer, Copilot::DiffHunk])) }
      attr_accessor :diff_hunks_by_id

      sig { returns(T.nilable(T::Hash[Integer, Copilot::DiffHunk])) }
      attr_accessor :manually_grouped_diff_hunks_by_id

      sig { returns(T.nilable(T::Array[Issue])) }
      attr_accessor :issues

      sig { returns(T.nilable(ChangeGroups::PromptBuilder::Result)) }
      attr_accessor :prompt

      sig { returns(T.nilable(T::Array[ChangeGroups::CopilotGenerator::GeneratedGroup])) }
      attr_accessor :generated_groups

      sig { returns(T.nilable(T::Array[PullRequests::ChangeGroup])) }
      attr_accessor :change_groups

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def current_for?(pull_request:)
        return false unless pull_request.id == pull_request_id
        return true if base_commit_oid.nil? && head_commit_oid.nil?

        pull_request.base_sha == base_commit_oid &&
          pull_request.head_sha == head_commit_oid
      end

      sig { returns(Integer) }
      def sync_race_detections
        @sync_race_detections ||= 0
      end

      sig { params(value: Integer).void }
      def sync_race_detections=(value)
        @sync_race_detections = value
      end

      def only_save_on_orchestration_end? = true

      def run_orchestration(...)
        super
      rescue *RETRYABLE_ERRORS
        return_to_last_async_retryable_step
        raise
      end

      job_start

      step :verify_pull_request_exists, max_attempts: 2, async_retryable: true do
        pull = pull_request

        unless pull.present?
          self.failure_reason = FailureReason::PullRequestNotFound
          next [:skipped, "Pull request not found"]
        end
      end

      step :verify_compare_repository_exists, async_retryable: false do
        pull = T.must_because(pull_request) { "Checked by :verify_pull_request_exists step" }
        begin
          pull.compare_repository
        rescue ActiveRecord::RecordNotFound
          self.failure_reason = FailureReason::CompareRepositoryNotFound
          next [:skipped, "Compare repository not found"]
        end
      end

      step :check_for_existing_groups, max_attempts: 2, async_retryable: true do
        pull = T.must_because(pull_request) { "Checked by :verify_pull_request_exists step" }

        if pull.current_change_groups.any?
          next [:skipped, "Pull request has up-to-date groups"]
        end
      end

      step :load_diff, max_attempts: 2, async_retryable: true do
        pull = T.must_because(pull_request) { "Checked by :verify_pull_request_exists step" }
        self.head_commit_oid = pull.head_sha
        self.base_commit_oid = pull.base_sha

        self.diff = pull.diffs
      end

      step :check_diff_size_limits, async_retryable: false do
        diff = T.must_because(self.diff) { "Provided by :load_diff step" }

        limit_config = PageData::Files::PageLimitConfig.new(
          repository: repository,
          user: actor,
          single_file_mode: true, # Force single file mode to enforce higher lines changed limits
        )
        if limit_config.exceeds_difflines_display_limits?(diff)
          self.failure_reason = FailureReason::DiffTooLarge
          next [:skipped, "Pull request is too large for grouping"]
        end
      end

      step :extract_diff_hunks, async_retryable: false do
        diff = T.must_because(self.diff) { "Provided by :load_diff step" }

        if pull_request&.owner.feature_flag_enabled?(:pr_group_generation_diff_filters, default: false)
          filtered_entries = PullRequests::Copilot::DiffsFilter.new(
            diffs: diff.entries,
            copilot_content_exclusion: copilot_content_exclusion_rules,
            override_max_files_limit: true,
            override_max_changes_limit: true
          ).to_a
          filtered_entry_paths = filtered_entries.collect(&:path)

          # Select diff entries to manually group excluding filtered diff entries
          # that will be used for generating groups with CAPI.
          manually_grouped_entries = diff.entries.select do |entry|
            filtered_entry_paths.exclude?(entry.path)
          end

          hunks_to_group = Copilot::DiffHunk.diffs_to_hunks(filtered_entries)
          manually_grouped_hunks = Copilot::DiffHunk.diffs_to_hunks(manually_grouped_entries)
          total_hunks_length = hunks_to_group.length + manually_grouped_hunks.length

          if total_hunks_length < MIN_DIFF_HUNKS
            self.failure_reason = FailureReason::DiffTooSmall
            next [:skipped, "Pull request has too few hunks"]
          end

          # Hunks need stable numerical IDs to be used in the prompt, and then
          # to interpret the output of the model.
          hunks_by_id = hunks_to_group.each.with_index.reduce({}) do |result, (hunk, idx)|
            result.merge((idx + 1) => hunk)
          end

          # For creating stable numerical IDs for our manually grouped hunks, we build
          # the hash keys using a combination of hunks_by_id.count + the reducer index + 1 to
          # ensure unique numerical IDs for each hash that don't conflict with keys in the `hunks_by_id` hash.
          manually_grouped_hunks_base_idx = hunks_by_id.count
          manually_grouped_hunks_by_id = manually_grouped_hunks.each.with_index.reduce({}) do |result, (hunk, idx)|
            result.merge((idx + manually_grouped_hunks_base_idx + 1) => hunk)
          end

          self.diff_hunks_by_id = hunks_by_id
          # Storing Hunk IDs that will not be used in CAPI prompt
          self.manually_grouped_diff_hunks_by_id = manually_grouped_hunks_by_id
        else
          hunks = Copilot::DiffHunk.diffs_to_hunks(diff.entries)

          if hunks.length < MIN_DIFF_HUNKS
            self.failure_reason = FailureReason::DiffTooSmall
            next [:skipped, "Pull request has too few hunks"]
          end

          # Hunks need stable numerical IDs to be used in the prompt, and then
          # to interpret the output of the model.
          hunks_by_id = hunks.each.with_index.reduce({}) do |result, (hunk, idx)|
            result.merge((idx + 1) => hunk)
          end

          self.diff_hunks_by_id = hunks_by_id
        end
      end

      step :find_associated_issues, max_attempts: 2, async_retryable: false do
        pull = T.must_because(pull_request) { "Checked by :verify_pull_request_exists step" }
        xrefs = CloseIssueReference.viewable_for(viewer: actor, issue: pull.issue, limit: REFERENCED_ISSUE_LIMIT)
        self.issues = xrefs.map(&:issue)
      end

      step :generate_copilot_prompt, async_retryable: false do
        pull_request = T.must_because(self.pull_request) { "Checked by :verify_pull_request_exists step" }
        diff_hunks_by_id = T.must_because(self.diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
        issues = T.must_because(self.issues) { "Provided by :find_associated_issues step" }

        prompt_builder = ChangeGroups::PromptBuilder.new(
          pull_request:,
          diff_hunks_by_id:,
          issues:,
        )
        prompt = prompt_builder.build

        # To avoid our Copilot request failing due to prompt's token size
        # we will skip the rest of the orchestration as Copilot generation retries will continue to fail.
        if prompt.total_length > MAX_PROMPT_LENGTH
          self.failure_reason = FailureReason::PromptTooLong
          next [:skipped, "Prompt contains too many tokens"]
        end

        self.prompt = prompt
      end

      MAX_GENERATE_CHANGE_GROUP_ATTEMPTS = 2
      step :generate_change_groups, max_attempts: MAX_GENERATE_CHANGE_GROUP_ATTEMPTS, async_retryable: false do
        prompt = T.must_because(self.prompt) { "Provided by the :generate_copilot_prompt step" }

        group_generator = ChangeGroups::CopilotGenerator.new(actor:, prompt:)
        result = group_generator.call
        attempts = T.must_because(self.make_change_groups_attempts) { "Defaults to 0" }

        case result
        when ChangeGroups::CopilotGenerator::Result::Success
          self.generated_groups = result.groups
        when ChangeGroups::CopilotGenerator::Result::Error
          log_info(
            "Group generation failed",
            "copilot_response" => result.copilot_response,
          )

          if result.retryable? && attempts < MAX_GENERATE_CHANGE_GROUP_ATTEMPTS
            with_write { update(make_change_groups_attempts: attempts + 1) }
            result.raise_as_cause_of!(Orchestration::RetryStepError)
          else
            self.failure_reason = FailureReason::CopilotError
            next [:failed, result.exception.message]
          end
        else
          T.absurd(result)
        end
      end

      step :validate_number_of_groups, async_retryable: false do
        generated_groups = T.must_because(self.generated_groups) { "Provided by the :generate_change_groups step" }

        if pull_request&.owner.feature_flag_enabled?(:pr_group_generation_diff_filters, default: false)
          manually_grouped_diff_hunks_by_id = T.must_because(self.manually_grouped_diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
          count = generated_groups.count

          # Increment count by 1 if there are any manually grouped diff hunks as these will be used
          # to create a generated group in validate_grouped_hunks.
          if manually_grouped_diff_hunks_by_id.length > 0
            count += 1
          end
        else
          count = generated_groups.count
        end

        GitHub.dogstats.distribution("pull_requests.change_groups.num_generated_groups", count)

        if count < MIN_GROUPS
          self.failure_reason = FailureReason::TooFewGroups
          next [:failed, "Too few groups were generated"]
        elsif count > MAX_GROUPS
          self.failure_reason = FailureReason::TooManyGroups
          next [:failed, "Too many groups were generated"]
        end
      end

      step :validate_grouped_hunks, async_retryable: false do
        if pull_request&.owner.feature_flag_enabled?(:pr_group_generation_diff_filters, default: false)
          diff_hunks_by_id = T.must_because(self.diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
          manually_grouped_diff_hunks_by_id = T.must_because(self.manually_grouped_diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
          generated_groups = T.must_because(self.generated_groups) { "Provided by the :generate_change_groups step" }

          assigned_diff_hunks = T.let(Set.new, T::Set[Integer])
          generated_groups.each do |group|
            assigned_diff_hunks.merge(group.hunk_ids)
          end

          valid_diff_hunks = diff_hunks_by_id.keys.to_set
          valid_other_diff_hunks = manually_grouped_diff_hunks_by_id.keys.to_set
          ungrouped_hunk_ids = valid_diff_hunks + valid_other_diff_hunks - assigned_diff_hunks
          invalid_hunk_ids = assigned_diff_hunks - valid_diff_hunks

          if invalid_hunk_ids.any?
            self.failure_reason = FailureReason::UnknownHunkIDs
            next [:failed, "Groups included unknown hunk IDs"]
          elsif ungrouped_hunk_ids.any?
            GitHub.dogstats.distribution(
              "pull_requests.change_groups.ungrouped_hunks.length",
              ungrouped_hunk_ids.length
            )

            generated_groups << ChangeGroups::CopilotGenerator::GeneratedGroup.new(
              name: "Other changes",
              hunk_ids: ungrouped_hunk_ids.to_a,
              priority: 0,
              bug_risk: 0,
              confidence: 0,
            )
          end
        else
          diff_hunks_by_id = T.must_because(self.diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
          generated_groups = T.must_because(self.generated_groups) { "Provided by the :generate_change_groups step" }

          assigned_diff_hunks = T.let(Set.new, T::Set[Integer])
          generated_groups.each do |group|
            assigned_diff_hunks.merge(group.hunk_ids)
          end

          valid_diff_hunks = diff_hunks_by_id.keys.to_set
          ungrouped_hunk_ids = valid_diff_hunks - assigned_diff_hunks
          invalid_hunk_ids = assigned_diff_hunks - valid_diff_hunks

          if invalid_hunk_ids.any?
            self.failure_reason = FailureReason::UnknownHunkIDs
            next [:failed, "Groups included unknown hunk IDs"]
          elsif ungrouped_hunk_ids.any?
            GitHub.dogstats.distribution(
              "pull_requests.change_groups.ungrouped_hunks.length",
              ungrouped_hunk_ids.length
            )

            generated_groups << ChangeGroups::CopilotGenerator::GeneratedGroup.new(
              name: "Other changes",
              hunk_ids: ungrouped_hunk_ids.to_a,
              priority: 0,
              bug_risk: 0,
              confidence: 0,
            )
          end
        end
      end

      step :build_change_groups, async_retryable: false do
        diff_hunks_by_id = T.must_because(self.diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
        generated_groups = T.must_because(self.generated_groups) { "Provided by the :generate_change_groups step" }

        # When feature flag is enabled, we need to look up hunks in both maps
        all_hunks_by_id = if pull_request&.owner.feature_flag_enabled?(:pr_group_generation_diff_filters, default: false)
          manually_grouped_diff_hunks_by_id = T.must_because(self.manually_grouped_diff_hunks_by_id) { "Provided by :extract_diff_hunks step" }
          diff_hunks_by_id.merge(manually_grouped_diff_hunks_by_id)
        else
          diff_hunks_by_id
        end

        self.change_groups = generated_groups.map do |group|
          change_group = PullRequests::ChangeGroup.new(
            actor:,
            pull_request:,
            repository:,
            name: group.name,
            base_commit_oid:,
            head_commit_oid:,
            priority: group.priority,
            bug_risk: group.bug_risk,
            confidence: group.confidence,
          )

          group.hunk_ids.each do |hunk_id|
            hunk = T.must_because(all_hunks_by_id[hunk_id]) { "Checked by :validate_grouped_hunks step" }
            change_group.add_hunk_position(hunk)
          end

          change_group
        end
      end

      step :persist_change_groups, max_attempts: 2, async_retryable: false do
        pull_request = T.must_because(self.pull_request) { "Checked by :verify_pull_request_exists step" }
        change_groups = T.must_because(self.change_groups) { "Provided by the :build_change_groups step" }

        # If the PR branch has moved while this orchestration was running, the
        # groups we just generated are no longer relevant, so we need to go
        # back to the start.
        pull_request.reload
        if base_commit_oid != pull_request.base_sha || head_commit_oid != pull_request.head_sha
          GitHub.dogstats.increment("pull_requests.change_groups.retry_after_sync")
          log_info(
            "PR sync race detected",
            "expected_base_commit_oid" => base_commit_oid,
            "expected_head_commit_oid" => head_commit_oid,
            "actual_base_commit_oid" => pull_request.base_sha,
            "actual_head_commit_oid" => pull_request.head_sha,
          )

          if sync_race_detections > 1
            next [:failed, "Detected multiple PR sync races"]
          else
            self.sync_race_detections += 1
            set_next_step :check_for_existing_groups
            next
          end
        end

        if change_groups.any?(&:invalid?)
          self.failure_reason = FailureReason::InvalidGroups
          next [:failed, "Generated groups are invalid"]
        end

        with_write do
          PullRequests::ChangeGroup.transaction do
            pull_request.all_change_groups.destroy_all
            change_groups.each(&:save!)
          end
        end
      end

      # Check if a failure reason represents a deterministic failure that shouldn't be retried
      # Excludes CopilotError (which could be transient) and Unknown (which is uncertain)
      sig { returns(T::Boolean) }
      def deterministic_failure?
        return false if self.failure_reason.nil?

        case self.failure_reason
        when FailureReason::CopilotError,
             FailureReason::Unknown
          false
        else
          true
        end
      end

      private

      def notify_pull_request_alive_channel
        return if pull_request.nil?

        event_payload = { base_commit_oid:, head_commit_oid: }
        channel = GitHub::WebSocket::Channels.pull_request_change_group_generation(pull_request)
        GitHub::WebSocket.notify_pull_request_channel(pull_request, channel, event_payload)
      end

      def return_to_last_async_retryable_step
        retry_from_step, index = get_step_by_name(step_name)
        return if retry_from_step.nil? || index.nil?

        while index > 0 && !retry_from_step.options[:async_retryable]
          index -= 1
          retry_from_step = self.class.all_steps[index]
        end

        if retry_from_step && retry_from_step.name != step_name
          with_write { update(step_name: retry_from_step.name) }
        end
      end

      sig { returns T.nilable(T::Array[T.nilable(String)]) }
      def copilot_content_exclusion_rules
        return if pull_request_id.nil?

        target = if pull_request&.base_repository&.fork?
          pull_request&.base_repository&.parent || pull_request&.base_repository
        else
          pull_request&.base_repository
        end

        owner = T.must(target).owner
        rules = if owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(owner)
          content_exclusion_rules_for_repo = ::Copilot::ContentExclusion.rules_for_repo(T.must(target))
          copilot_content_exclusion_paths = content_exclusion_rules_for_repo.flat_map { |_config, rules| rules.collect(&:patterns) }.flatten.uniq
          copilot_content_exclusion_paths.map { |path| path[0] == "/" ? path[1..-1] : path }
        end
        T.let(rules, T.nilable(T::Array[T.nilable(String)]))
      end
    end
  end
end
