# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class MergeQueuesGroupTest < GitHub::TestCase
    setup do
      @base_sha = 0
      @head_sha = 1
    end

    context ".find_next" do
      test "it selects solo PRs when they are at the head" do
        configuration = build_configuration
        solo_entry = build_entry(solo: true, configuration:)
        queued_entry = build_entry(configuration:)

        group = Group.find_next(
          configuration:,
          entries: [solo_entry, queued_entry],
        )

        assert_equal [solo_entry], group.entries
        assert_equal Group::State::Mergeable, group.state
        assert_equal solo_entry, group.head_entry!
      end

      test "it selects the best PR when the minimum group size is met" do
        configuration = build_configuration(
          min_merge_entries_size: 1,
        )
        queued_entry = build_entry(configuration:)

        group = Group.find_next(
          configuration:,
          entries: [queued_entry],
        )

        assert_equal [queued_entry], group.entries
        assert_equal Group::State::Mergeable, group.state
        assert_equal queued_entry, group.head_entry!
      end

      test "ignores minimum group size requirements when the next entry is solo" do
        configuration = build_configuration(
          min_merge_entries_size: 3,
        )
        queued_entry = build_entry(configuration:)
        solo_entry = build_entry(solo: true, configuration:)

        group = Group.find_next(
          configuration:,
          entries: [queued_entry, solo_entry],
        )

        assert_equal [queued_entry], group.entries
        assert_equal Group::State::Mergeable, group.state
        assert_equal queued_entry, group.head_entry!
      end

      test "has no head entry if the size requirements are not yet met" do
        configuration = build_configuration(
          min_merge_entries_size: 3,
        )
        queued_entry = build_entry(configuration:)

        group = Group.find_next(
          configuration:,
          entries: [queued_entry],
        )

        assert_equal [queued_entry], group.entries
        assert_equal Group::State::MinimumSizeNotMet, group.state
        assert_raises(Group::NotMergeableError) { group.head_entry! }
      end

      test "it will allow a smaller group size if it has waited long enough" do
        configuration = build_configuration(
          min_merge_entries_size: 3,
          max_wait_for_min_merge_entries_size: 1.minute,
        )
        queued_entry = build_entry(created_at: 2.minutes.ago, configuration:)

        group = Group.find_next(
          configuration:,
          entries: [queued_entry],
        )

        assert_equal [queued_entry], group.entries
        assert_equal Group::State::Mergeable, group.state
        assert_equal queued_entry, group.head_entry!
      end

      test "it will not exceed the maximum group size" do
        configuration = build_configuration(
          max_merge_entries_size: 3,
        )

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal entries.take(3), group.entries
      end

      test "it will allow failing entries in the group when the grouping strategy allows it" do
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
        )

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Unmergeable.failed_checks),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Unmergeable.failed_checks),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal entries.take(4), group.entries
      end

      test "it will not allow failing entries in the group when the grouping strategy forbids it" do
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::AllGreen,
        )

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Unmergeable.failed_checks),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Unmergeable.failed_checks),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal entries.take(2), group.entries
      end

      test "it will return the existing locked group if there is one" do
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
        )

        entries = [
          build_entry(configuration:, locked: true),
          build_entry(configuration:, locked: true),
          build_entry(configuration:, locked: true),
          build_entry(configuration:, locked: false),
          build_entry(configuration:, locked: false),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal entries.take(3), group.entries
      end

      test "it will ignore entries without a head SHA" do
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::AllGreen,
        )

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Unmergeable.merge_conflict, base_sha: "", head_sha: ""),
          build_entry(configuration:, state: Entry::State::Unmergeable.already_merged, base_sha: "", head_sha: ""),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal [entries[0], entries[1], entries[4]], group.entries
      end

      test "it will stop if the Git graph is not continuous" do
        enable_feature_flag(:merge_queue_group_verify_git_graph)

        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::AllGreen,
        )

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new, base_sha: "a", head_sha: "b"),
          build_entry(configuration:, state: Entry::State::Mergeable.new, base_sha: "b", head_sha: "c"),
          # Entry with base_sha=c, head_sha=d has been removed!
          build_entry(configuration:, state: Entry::State::Mergeable.new, base_sha: "d", head_sha: "e"),
          build_entry(configuration:, state: Entry::State::Mergeable.new, base_sha: "e", head_sha: "f"),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal [entries[0], entries[1]], group.entries
      end

      test "it will not include solo entries in a group" do
        configuration = build_configuration

        entries = [
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new, solo: true),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal [entries[0], entries[1]], group.entries
      end

      test "it will not include queued entries in a group" do
        configuration = build_configuration

        # This situation can arise half way through the background job
        # running, e.g. if the first entry was removed from the queue and
        # the entries are being rebuilt one by one.
        #
        # Deploy-then-merge queues use synchronous operations, like the GraphQL
        # LockMergeQueue mutation, which can fire during a background job run.
        entries = [
          build_entry(configuration:, state: Entry::State::Queued.new, head_sha: ""),
          build_entry(configuration:, state: Entry::State::Queued.new, head_sha: ""),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
          build_entry(configuration:, state: Entry::State::Mergeable.new),
        ]

        group = Group.find_next(configuration:, entries:)

        assert_equal [], group.entries
      end
    end

    private

    sig do
      params(
        configuration: Configuration,
        solo: T::Boolean,
        created_at: T.nilable(Time),
        state: T.nilable(Entry::State),
        locked: T::Boolean,
        head_sha: T.nilable(String),
        base_sha: T.nilable(String),
      ).returns(Entry)
    end
    def build_entry(configuration:, solo: false, created_at: nil, state: nil, locked: false, head_sha: nil, base_sha: nil)
      Entry.new(
        state: state || Entry::State::Mergeable.new,
        locked:,
        solo:,
        merge_queue_entry_id: merge_queue_entry_id_sequence.next,
        pull_request_number: pull_request_number_sequence.next,
        pull_request_id: pull_request_id_sequence.next,
        created_at: created_at || Time.now,
        requested_checks: [],
        head_sha: head_sha || (@head_sha += 1).to_s(16).rjust(40, "0"),
        base_sha: base_sha || (@base_sha += 1).to_s(16).rjust(40, "0"),
      )
    end

    sig do
      params(
        min_merge_entries_size: Integer,
        max_merge_entries_size: Integer,
        max_wait_for_min_merge_entries_size: ActiveSupport::Duration,
        grouping_strategy: IConfiguration::GroupingStrategy,
      ).returns(Configuration)
    end
    def build_configuration(min_merge_entries_size: 1, max_merge_entries_size: 5, max_wait_for_min_merge_entries_size: 5.minutes, grouping_strategy: IConfiguration::GroupingStrategy::AllGreen)
      Configuration.new(
        actor_controlled_merging: false,
        max_concurrency: 5,
        max_attempts: 1,
        max_wait_for_min_merge_entries_size:,
        min_merge_entries_size:,
        max_merge_entries_size:,
        check_response_timeout: 5.minutes,
        grouping_strategy:,
      )
    end

    sig { returns(T::Enumerator[Integer]) }
    def merge_queue_entry_id_sequence
      @merge_queue_entry_id_sequence ||= build_sequence(from: 1)
    end

    sig { returns(T::Enumerator[Integer]) }
    def pull_request_number_sequence
      @pull_request_number_sequence ||= build_sequence(from: 1001)
    end

    sig { returns(T::Enumerator[Integer]) }
    def pull_request_id_sequence
      @pull_request_id_sequence ||= build_sequence(from: 101)
    end

    sig { params(from: Integer).returns(T::Enumerator[Integer]) }
    def build_sequence(from:)
      Enumerator.new do |yielder|
        id = from
        loop do
          yielder << id
          id += 1
        end
      end
    end
  end
end
