# typed: strict
# frozen_string_literal: true

module MergeQueues
  # A group of Entry instances that could be merged together as a group.
  class Group
    extend T::Generic

    EntryType = type_member { { upper: Groupable } }

    module Groupable
      extend T::Helpers

      interface!
      requires_ancestor { Object }

      sig { abstract.returns(T::Boolean) }
      def locked?; end

      sig { abstract.returns(T::Boolean) }
      def queued?; end

      sig { abstract.returns(T::Boolean) }
      def solo?; end

      sig { abstract.returns(T::Boolean) }
      def mergeable?; end

      sig { abstract.returns(T.nilable(String)) }
      def head_sha; end

      sig { abstract.returns(T.nilable(String)) }
      def base_sha; end

      sig { abstract.returns(T.any(ActiveSupport::TimeWithZone, Time)) }
      def created_at; end
    end

    class State < T::Enum
      enums do
        Mergeable = new(:mergeable)
        Empty = new(:empty)
        MinimumSizeNotMet = new(:minimum_size_not_met)
      end
    end

    class NotMergeableError < StandardError; end

    sig do
      type_parameters(:E)
        .params(configuration: IConfiguration, entries: T::Array[T.all(T.type_parameter(:E), Groupable)])
        .returns(Group[T.all(T.type_parameter(:E), Groupable)])
    end
    def self.find_next(configuration:, entries:)
      return Group.new(configuration:, entries: []) if entries.blank?

      # If there are any locked entries, they have already been identified
      # as the next group.
      if locked_entries = entries.take_while(&:locked?).presence
        return Group.new(
          configuration:,
          entries: locked_entries,
          ignore_size_limits: true,
        )
      end

      # In the event of a solo PR being at the head of our list, that is the
      # only thing we should consider merging.
      if (first_entry = entries.first) && first_entry.solo?
        if first_entry.mergeable?
          return Group.new(
            configuration:,
            entries: [first_entry],
            ignore_size_limits: true,
          )
        else
          return Group.new(configuration:, entries: [])
        end
      end

      # We want to grab up to the max group size, excluding anything we can't
      # group (solo entires, queued entries, etc.)
      candidates = entries.lazy
        .take_while { |entry| !entry.solo? && !entry.queued? }
        .reject { |entry| entry.head_sha.blank? }
        .take(configuration.max_merge_entries_size)
        .to_a

      # Verify that we have an unbroken chain of `base_sha` and `head_sha`
      # within the group. If an entry has been just removed from the queue but
      # the background job hasn't re-run since, we might have some entries
      # that are still marked as mergeable but are referencing outdated Git
      # commits.
      previous_entry = T.let(nil, T.nilable(Groupable))
      candidates = candidates.take_while do |entry|
        next false if previous_entry.present? && entry.base_sha != previous_entry.head_sha
        previous_entry = entry
        true
      end

      # Select the candidates that satisfy the merging strategy
      group = case grouping_strategy = configuration.grouping_strategy
      when IConfiguration::GroupingStrategy::HeadGreen
        # Grab the last mergeable entry to most efficiently merge.
        candidates.reverse_each.drop_while { |entry| !entry.mergeable? }.reverse
      when IConfiguration::GroupingStrategy::AllGreen
        candidates.take_while(&:mergeable?)
      else
        T.absurd(grouping_strategy)
      end

      # If the next entry is a solo? then we have to merge this collection
      # regardless of any group size requirements.
      next_entry = entries[group.size]
      Group.new(
        configuration:,
        entries: group,
        ignore_size_limits: next_entry&.solo? || false,
      )
    end

    class PartitionResult < T::Struct
      extend T::Generic

      EntryType = type_member { { upper: Groupable } }

      const :active_group, Group[T.all(EntryType, Groupable)]
      const :ungrouped_entries, T::Array[EntryType]
    end

    sig do
      type_parameters(:E)
        .params(configuration: IConfiguration, entries: T::Array[T.all(T.type_parameter(:E), Groupable)])
        .returns(PartitionResult[T.all(T.type_parameter(:E), Groupable)])
    end
    def self.partition(configuration:, entries:)
      active_group = find_next(configuration:, entries:)
      ungrouped_entries = entries - active_group.entries

      PartitionResult[T.all(T.type_parameter(:E), Groupable)].new(
        active_group:,
        ungrouped_entries:,
      )
    end

    sig { returns(T::Array[EntryType]) }
    attr_reader :entries

    sig { params(configuration: IConfiguration, entries: T::Array[EntryType], ignore_size_limits: T::Boolean).void }
    def initialize(configuration:, entries:, ignore_size_limits: false)
      @configuration = configuration
      @entries = entries
      @ignore_size_limits = ignore_size_limits
    end

    sig { returns(EntryType) }
    def head_entry!
      raise NotMergeableError unless state == State::Mergeable
      T.must(@entries.last)
    end

    sig { returns(EntryType) }
    def base_entry!
      raise NotMergeableError unless state == State::Mergeable
      T.must(@entries.first)
    end

    sig { returns(State) }
    def state
      if @entries.empty?
        State::Empty
      elsif enforce_size_limits? && too_small? && can_wait_for_more_entries?
        State::MinimumSizeNotMet
      else
        State::Mergeable
      end
    end

    sig { returns(T::Boolean) }
    def empty?
      state == State::Empty
    end

    sig { returns(T::Boolean) }
    def locked?
      @entries.last&.locked? || false
    end

    sig { returns(T::Boolean) }
    def solo?
      @entries.last&.solo? || false
    end

    private

    sig { returns(T::Boolean) }
    def enforce_size_limits?
      !@ignore_size_limits
    end

    sig { returns(T::Boolean) }
    def too_small?
      @entries.size < @configuration.min_merge_entries_size
    end

    sig { returns(T::Boolean) }
    def can_wait_for_more_entries?
      return true unless @configuration.max_wait_for_min_merge_entries_size.present?

      started_at = @entries.map(&:created_at).compact.min
      (Time.current - started_at) <= @configuration.max_wait_for_min_merge_entries_size
    end
  end
end
