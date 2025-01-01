# typed: strict
# frozen_string_literal: true

module Stafftools
  module Repositories
    class MergeQueueComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(MergeQueue) }
      attr_reader :merge_queue

      sig { returns(::Repository) }
      attr_reader :repository

      sig { params(merge_queue: MergeQueue, repository: ::Repository, page: Integer, per_page: Integer).void }
      def initialize(merge_queue:, repository:, page: 1, per_page: 15)
        @merge_queue = merge_queue
        @repository = repository
        @page = page
        @per_page = per_page
      end

      sig { returns(MergeQueues::IConfiguration) }
      memoize def configuration
        MergeQueues.configuration_for(merge_queue)
      end

      sig { returns(String) }
      def grouping_strategy_description
        case strategy = configuration.grouping_strategy
        when MergeQueues::IConfiguration::GroupingStrategy::AllGreen
          "All entries must pass required checks"
        when MergeQueues::IConfiguration::GroupingStrategy::HeadGreen
          "Only the head entry must pass required checks"
        else
          T.absurd(strategy)
        end
      end

      sig { returns(T::Enumerable[MergeQueueEntry]) }
      memoize def merge_queue_entries
        merge_queue.entries
          .order(position: :asc)
          .includes(:enqueuer, pull_request: :issue)
          .paginate(page: @page, per_page: @per_page)
      end

      sig { params(entry: MergeQueueEntry).returns(Primer::Beta::Label) }
      def state_label(entry)
        entry_state = state(entry)
        scheme = :secondary
        label = entry_state.class.name

        case entry_state
        when MergeQueues::Entry::State::Waiting, MergeQueues::Entry::State::Queued
          scheme = :primary
          label = "Queued"
        when MergeQueues::Entry::State::AwaitingChecks
          scheme = :attention
          label = "Waiting for checks"
        when MergeQueues::Entry::State::Mergeable
          scheme = :success
          label = "Mergeable"
        when MergeQueues::Entry::State::Unmergeable
          scheme = :danger
          label = case reason = entry_state.reason
          when MergeQueues::Entry::RemovalReason::Unknown, MergeQueues::Entry::RemovalReason::GitTreeInvalid then "Unmergeable"
          when MergeQueues::Entry::RemovalReason::Manual then "Manually removed"
          when MergeQueues::Entry::RemovalReason::Merged then "Merged"
          when MergeQueues::Entry::RemovalReason::MergeConflict then "Merge conflict"
          when MergeQueues::Entry::RemovalReason::FailedChecks then "Failed all CI attempts"
          when MergeQueues::Entry::RemovalReason::ChecksTimedOut then "CI timed out"
          when MergeQueues::Entry::RemovalReason::AlreadyMerged then "Already merged"
          when MergeQueues::Entry::RemovalReason::QueueCleared then "Queue cleared"
          when MergeQueues::Entry::RemovalReason::RollBack then "Rolled back"
          when MergeQueues::Entry::RemovalReason::InvalidMergeCommit then "Merge contents invalid"
          when MergeQueues::Entry::RemovalReason::BranchProtections then "Branch protection rules not met"
          else
            T.absurd(reason)
          end
        else
          T.absurd(entry_state)
        end

        Primer::Beta::Label.new(scheme:).with_content(label)
      end

      private

      sig { params(entry: MergeQueueEntry).returns(MergeQueues::Entry::State) }
      def state(entry)
        state_by_entry_id.fetch(entry.id)
      end

      sig { returns(T::Hash[Integer, MergeQueues::Entry::State]) }
      memoize def state_by_entry_id
        factory = MergeQueues::Factory.new(
          repository,
          merge_queue,
          entries: merge_queue_entries.to_a,
        )

        factory.to_entry_list.map { |entry| [entry.merge_queue_entry_id, entry.state] }.to_h
      end
    end
  end
end
