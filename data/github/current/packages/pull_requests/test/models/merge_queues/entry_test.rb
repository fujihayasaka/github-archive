# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class EntryTest < GitHub::TestCase
    include HydroTestHelpers

    context "State" do
      test "is valid for use with the MergeQueueEntry model" do
        Entry::State.sealed_subclasses.each do |klass|
          assert_nothing_raised { build(:merge_queue_entry, state: klass.const_get(:VALUE)) }
        end
      end

      test "can be derrived from its MergeQueueEntry model value" do
        Entry::State.sealed_subclasses.each do |klass|
          value = klass.const_get(:VALUE)
          assert_equal klass, Entry::State.deserialize(value)
        end
      end

      test "has a valid HYDRO_ENUM_VALUE" do
        hydro_enum = Hydro::Schemas::Github::MergeQueue::V1::Entities::MergeQueueEntry::State

        Entry::State.sealed_subclasses.each do |state_class|
          symbol_value = assert_nothing_raised { state_class.const_get(:HYDRO_ENUM_VALUE) }
          integer_value = hydro_enum.resolve(symbol_value)
          refute_nil integer_value, "#{symbol_value} needs to be added to the Hydro schema in #{hydro_enum}"
        end
      end
    end

    context "RemovalReason" do
      test ".deserialize can handle all legacy removal reasons" do
        MergeQueueEntry::REMOVAL_REASONS.keys.each do |legacy_reason|
          refute_equal Entry::RemovalReason::Unknown, Entry::RemovalReason.deserialize(legacy_reason),
            "Deserialized legacy reason #{legacy_reason.inspect} as Unknown"
        end
      end

      test ".deserialize can handle blank values" do
        [nil, "", :""].each do |blank_value|
          assert_equal Entry::RemovalReason::Unknown, Entry::RemovalReason.deserialize(blank_value)
        end
      end

      test "#to_hydro_enum_value can produce a valid Hydro enum member" do
        hydro_enum = Hydro::Schemas::Github::MergeQueue::V1::MergeQueueEntryEvent::RemovalReason
        Entry::RemovalReason.values.each do |reason|
          symbol_value = reason.to_hydro_enum_value
          integer_value = hydro_enum.resolve(symbol_value)
          refute_nil integer_value, "#{symbol_value} needs to be added to the Hydro schema in #{hydro_enum}"
        end
      end
    end

    context "state checks" do
      test "is still pending when only awaiting checks" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          requested_checks: [
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Pending,
              attempts: 1,
              max_attempts: 1,
              supports_retry: true
            )
          ]
        )

        refute entry.passing_checks?
        refute entry.failing_checks?
        refute entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is passing when all checks are passing" do
        entry = build_entry(
          requested_checks: 2.times.map do
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Success,
              attempts: 1,
              max_attempts: 1,
              supports_retry: true
            )
          end,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
        )

        assert entry.passing_checks?
        refute entry.failing_checks?
        refute entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is not passing or failing when no checks were requested" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current
          )
        )

        refute entry.passing_checks?
        refute entry.failing_checks?
        refute entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is failing when all checks are failing without any remaining retries" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          requested_checks: [
            build_requested_check(state: MergeQueues::Entry::RequestedCheck::State::Success),
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Failed,
              attempts: 1,
              max_attempts: 1,
              supports_retry: true
            )
          ]
        )

        refute entry.passing_checks?
        assert entry.failing_checks?
        refute entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is failing when all checks are failing without remaining attempts but nothing retryable" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          requested_checks: [
            build_requested_check(state: MergeQueues::Entry::RequestedCheck::State::Success),
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Failed,
              attempts: 1,
              max_attempts: 2,
              supports_retry: false
            )
          ]
        )

        refute entry.passing_checks?
        assert entry.failing_checks?
        refute entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is retryable when checks are failing with remaining attempts" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          requested_checks: [
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Failed,
              attempts: 1,
              max_attempts: 2,
              supports_retry: true
            )
          ]
        )

        refute entry.passing_checks?
        refute entry.failing_checks?
        assert entry.retryable_checks?
        refute entry.timed_out_checks?
      end

      test "it is timed out when checks are pending without remaining attempts" do
        entry = build_entry(
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          requested_checks: [
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Pending,
              requested_at: 10.minutes.ago,
              timeout_after: 1.minute,
              attempts: 1,
              max_attempts: 1,
              supports_retry: true
            )
          ]
        )

        refute entry.passing_checks?
        refute entry.failing_checks?
        refute entry.retryable_checks?
        assert entry.timed_out_checks?
      end

      test "it is timed out when state is unmergeable and entry removed due to timed-out checks", skip_if_feature_disabled: :merge_queue_expand_timed_out_check_runs_conditions do
        entry = build_entry(
          state: Entry::State::Unmergeable.new(
            reason: MergeQueues::Entry::RemovalReason::ChecksTimedOut
          ),
          requested_checks: [
            build_requested_check(
              state: MergeQueues::Entry::RequestedCheck::State::Pending,
              attempts: 1,
              max_attempts: 1,
              supports_retry: true
            )
          ]
        )

        refute entry.passing_checks?
        refute entry.failing_checks?
        refute entry.retryable_checks?
        assert entry.timed_out_checks?
      end
    end

    context "#as_json" do
      test "excludes configuration by default" do
        entry = build_entry(state: Entry::State::Queued.new)
        serialized = entry.as_json

        assert serialized.has_key?("state")
        refute serialized.has_key?("configuration")
      end
    end

    sig do
      params(
        state: Entry::RequestedCheck::State,
        attempts: Integer,
        max_attempts: Integer,
        timeout_after: ActiveSupport::Duration,
        supports_retry: T::Boolean,
        requested_at: Time
      ).returns(Entry::RequestedCheck)
    end
    def build_requested_check(state:, attempts: 1, max_attempts: 0, timeout_after: 60.minutes, supports_retry: true, requested_at: Time.current.to_time)
      Entry::RequestedCheck.new(
        name: "check-#{rand(100)}",
        attempts:,
        max_attempts:,
        timeout_after:,
        requested_at:,
        state:,
        supports_retry:
      )
    end

    sig { returns(Entry::RequiredCheck) }
    def build_required_checks
      Entry::RequiredCheck.new(name: "required-check-#{rand(100)}")
    end

    sig do
      params(
        state: Entry::State,
        attempts: Integer,
        requested_checks: T.nilable(T::Array[Entry::RequestedCheck]),
      ).returns(Entry)
    end
    def build_entry(state:, attempts: 1, requested_checks: nil)
      requested_checks ||= []

      Entry.new(
        merge_queue_entry_id: 1,
        pull_request_number: 2,
        pull_request_id: 3,
        state:,
        attempts:,
        created_at: Time.now,
        requested_checks:,
      )
    end
  end

  class EntryEquivalenceTest < GitHub::TestCase
    # In order for MergeQueues::Group to operate on both MergeQueues::Entry
    # and MergeQueueEntry instances, we must ensure that their implementations
    # of the `#mergeable?` method agree with each other.

    if GitHub.merge_queues_enabled?
      test "#mergeable?" do
        repository = create(:repository)
        queue = build_stubbed(:merge_queue, repository:)

        MergeQueues::Entry::State.sealed_subclasses.each do |state_class|
          state = build_state(T.cast(state_class, Entry::State::Classes))
          entry = build_entry(state:)
          model = build_stubbed(:merge_queue_entry, queue:, state: state_class.const_get(:VALUE))

          assert_equal(
            entry.mergeable?,
            model.mergeable?,
            "Mismatch for state #{state}: "\
              "entry #{entry.mergeable? ? "is" : "is not"} mergeable, "\
              "but model #{model.mergeable? ? "is" : "is not"} mergeable)"
          )
        end
      end
    end

    private

    sig { params(state: Entry::State).returns(Entry) }
    def build_entry(state:)
      Entry.new(
        merge_queue_entry_id: 1,
        pull_request_number: 2,
        pull_request_id: 3,
        state:,
        attempts: 1,
        created_at: Time.now,
        requested_checks: [],
      )
    end

    sig { params(state_class: Entry::State::Classes).returns(Entry::State) }
    def build_state(state_class)
      if state_class == MergeQueues::Entry::State::AwaitingChecks
        state_class.new(checks_requested_at: Time.current)
      elsif state_class == MergeQueues::Entry::State::Unmergeable
        state_class.new(reason: MergeQueues::Entry::RemovalReason::MergeConflict)
      elsif state_class.instance_method(:initialize).arity == 0
        T.unsafe(state_class).new
      else
        raise "This test needs to be updated when there are new state classes with initializer arguments"
      end
    end
  end
end
