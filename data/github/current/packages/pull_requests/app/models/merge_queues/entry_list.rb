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
  end
end
