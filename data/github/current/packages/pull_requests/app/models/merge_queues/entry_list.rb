# typed: strict
# frozen_string_literal: true

module MergeQueues
  # A container object that ensures FIFO order of Entry objects.
  class EntryList
    extend T::Generic
    include Enumerable
    Elem = type_member { { fixed: Entry } }

    sig { params(entries: T::Array[Entry]).void }
    def initialize(entries = [])
      @entries = entries
    end

    # Convert the EntryList to something that can be logged.
    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def serialize
      map(&:as_json)
    end

    # Yield all non "waiting" entries.
    sig do
      override.params(
        blk: T.proc.params(arg0: Entry).returns(BasicObject)
      ).returns(EntryList)
    end
    def each(&blk)
      @entries.lazy.without(&:waiting?).each(&blk)
      self
    end

    sig { returns(T::Boolean) }
    def empty?
      @entries.empty?
    end

    # Remove an Entry from the EntryList.
    sig { params(entry: Entry).returns(T.nilable(Entry)) }
    def delete(entry)
      @entries.delete(entry)
    end

    # Find all Entries before and including the given Entry.
    sig { params(last_entry: Entry).returns(T::Array[Entry]) }
    def up_to_and_including(last_entry)
      if index = @entries.index(last_entry)
        @entries.take(index + 1)
      else
        []
      end
    end

    # All entries that come after the given Entry.
    sig { params(last_entry: Entry).returns(T::Array[Entry]) }
    def after(last_entry)
      if index = @entries.index(last_entry)
        @entries.drop(index + 1)
      else
        []
      end
    end

    # Find the Entry that comes before the given Entry that can be merged in a future state.
    sig { params(entry: Entry).returns(T.nilable(Entry)) }
    def buildable_ancestor_of(entry)
      index = @entries.index(entry)

      if index && index != 0
        @entries.lazy
          .take(index)
          .reverse_each
          .find { |e| e.merge_conflict? == false && e.head_sha.present? }
      else
        nil
      end
    end

    # Find the Entry after the given Entry.
    sig { params(entry: Entry).returns(T.nilable(Entry)) }
    def descendent_of(entry)
      if index = @entries.index(entry)
        @entries[index + 1]
      end
    end

    # Find all entries in the same stack with a higher stack_position.
    sig { params(entry: Entry).returns(T::Array[Entry]) }
    def stack_descendants_of(entry)
      return [] unless entry.stacked?
      @entries.select { |candidate| candidate.stack_descendant_of?(entry) }
    end

    # Find the queue entry representing the next entry from a given stack
    sig { params(entry: Entry).returns(T.nilable(Entry)) }
    def next_entry_in_same_stack(entry)
      candidate = stack_descendants_of(entry).first
      return if candidate.nil?

      # These cannot be `nil` when we have found a stack descendant for the
      # given entry.
      stack_info = T.must(entry.stack_info)
      candidate_stack_info = T.must(candidate.stack_info)

      if candidate_stack_info.position != stack_info.position + 1
        # This should be impossible, because we should have already called
        # `#validate_stack` for each stack present in the queue to verify
        # the entries do have contiguous positions.
        GitHub.logger.info(
          "Next merge queue entry for stack does not have contiguous position",
          "gh.pull_request_stacks.id" => entry.stack_id,
          "gh.pull_request_stacks.position" => candidate_stack_info.position,
        )
        return nil
      end

      candidate
    end

    # Returns the entry and all same-stack descendants when stacked and contiguous, or just the entry.
    sig { params(entry: Entry).returns(T::Array[Entry]) }
    def with_stack(entry)
      [entry] + stack_descendants_of(entry)
    end

    # Age of the oldest entry in the Queue.
    sig { returns(T.nilable(Time)) }
    def started_at
      map(&:created_at).compact.min
    end

    # Determine the next best group of entries to attempt to merge.
    sig { params(configuration: IConfiguration).returns(Group[Entry]) }
    def next_group(configuration)
      Group.find_next(configuration:, entries: @entries)
    end

    # Filter the collection to just unlocked Entries.
    sig { returns(T::Array[Entry]) }
    def unlocked
      reject(&:locked?)
    end

    # Find the head_sha of a locked group, if we have one.
    sig { returns(T.nilable(String)) }
    def locked_head_sha
      # TODO: Should this live with the Group?
      take_while(&:locked?).last&.head_sha
    end

    # Returns all entries with the given stack_id, in queue order.
    sig { params(stack_id: Integer).returns(T::Array[Entry]) }
    def for_stack_id(stack_id)
      @entries.select { |e| e.stack_id == stack_id }
    end

    sig { returns(T::Set[Integer]) }
    def stack_ids = @entries.filter_map(&:stack_id).to_set

    # Checks that the queue entires representing stacked PRs are in a valid
    # state.
    sig { params(stack_id: Integer).returns(StackValidity) }
    def validate_stack(stack_id)
      entries = @entries.select { _1.stack_id == stack_id }
      return StackValidity.not_found if entries.empty?

      # Verify that the first entry belonging to the stack is the bottom-most
      # unmerged item in the stack.
      first_entry = T.must(entries.min_by { _1.stack_info&.position.to_i })
      if !first_entry.parent_stack_entry_merged?
        return StackValidity::UnmergedParent.new(entries:)
      end

      # If there is only 1 entry from this stack, further checks can be
      # skipped.
      if entries.length == 1
        return StackValidity.ok
      end

      # Verify that the items from the stack have the same order in the queue
      # that they have in the stack, and that there are no gaps.
      prev_position = T.must(first_entry.stack_info&.position) - 1
      entries.each.with_index do |entry, idx|
        position = T.must(entry.stack_info&.position)
        if position != prev_position + 1
          return StackValidity::NotContiguous.new(entries: entries[idx..] || [])
        end
        prev_position = position
      end

      StackValidity.ok
    end
  end
end
