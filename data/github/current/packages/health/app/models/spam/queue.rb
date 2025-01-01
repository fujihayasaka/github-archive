# typed: false
# frozen_string_literal: true

module Spam
  class Queue
    attr_reader :sd

    def initialize(datasource_name, description = nil)
      @sd = begin
        spam_datasource = SpamDatasource.find_by_name(datasource_name)
        spam_datasource ||= begin
          ActiveRecord::Base.connected_to(role: :writing) do
            SpamDatasource.create(name: datasource_name, description: description)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134041
      end
    end

    def older_than(cutoff)
      sd.entries.reload.where("created_at < ?", cutoff)
    end

    def newer_than(cutoff)
      sd.entries.reload.where("created_at > ?", cutoff)
    end

    def clear_older_than(cutoff)
      older_than(cutoff).destroy_all
    end

    def drop_these(collection)
      collection.each { |element| drop_this element }
    end

    # drop_this :: [String] -> Boolean
    #
    # If the given value is in the queue, drop its entry and return true.
    # Return false otherwise.
    #
    # Example:
    #
    #   ipq.drop_this("127.0.0.1")
    #     # => [true | false]
    #
    def drop_this(value)
      if entry = find_entry_by_value(value)
        entry.destroy
        true
      else
        false
      end
    end

    # is_member? :: [String] -> Boolean
    #
    # Checks whether the given value is in the queue.
    #
    # Example:
    #
    #   ipq.is_member?("127.0.0.1")
    #     # => false
    #
    def is_member?(ip)
      !!find_entry_by_value(ip)
    end

    # size :: [Integer] -> Array[String, String, ...]
    #
    # Returns an Array of the first Integer SpamDatasourceEntries' values in SpamDatasource.
    #
    # Example:
    #
    #   ipq.peek(3)
    #     # => #<Array[String, String, String]>
    #
    def peek(number = 10)
      sd.entries.reload.first(number).collect(&:value)
    end

    # size :: [String] -> SpamDatasourceEntry<[String]>
    #
    # Creates a new SpamDatasourceEntry in SpamDatasource with the specified value.
    #
    # Example:
    #
    #   ipq.push("127.0.0.1")
    #     # => #<SpamDatasource value: "127.0.0.1">
    #
    def push(value)
      find_entry_by_value(value) ||
        sd.entries.create(value: value)
    end

    # size :: nil -> Integer
    #
    # Returns the count of entries in the SpamDatasource.
    #
    # Example:
    #
    #   ipq.size
    #     # => 12
    #
    def size
      sd.entries.count
    end

    private

    def find_entry_by_value(value)
      sd.entries.where(value: value).first
    end
  end
end
