# typed: true
# frozen_string_literal: true

class TaskList
  # Provides a summary of provided TaskList `items`.
  #
  # `items` is an Array of TaskList::Item objects.
  class Summary
    attr_reader :items

    def initialize(items)
      @items = items
    end

    # Public: returns true if there are any TaskList::Item objects.
    def items?
      item_count > 0
    end

    # Public: returns the number of TaskList::Item objects.
    def item_count
      items.size
    end

    # Public: returns the number of complete TaskList::Item objects.
    def complete_count
      items.count { |i| i.complete? }
    end

    # Public: returns the number of incomplete TaskList::Item objects.
    def incomplete_count
      items.count { |i| !i.complete? }
    end

    def platform_type_name
      "TaskListSummary"
    end

    PACKER = lambda do |obj|
      list = obj.items.map do |item|
        { checkbox_text: item.checkbox_text,
          permalink: item.permalink
        }
      end
      GitHub::Cache::Codec.factory.pack(list)
    end

    UNPACKER = lambda do |data|
      list = GitHub::Cache::Codec.factory.unpack(data)
      items = list.map do |i|
        item = Item.new(i[:checkbox_text])
        item.permalink = i[:permalink]
        item
      end
      Summary.new(items)
    end

    GitHub::Cache::Codec.register_type(
      GitHub::Cache::Codec::TASK_LIST_SUMMARY_TYPE,
      self)
  end
end
