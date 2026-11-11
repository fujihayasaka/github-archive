# typed: true
# frozen_string_literal: true

module UserLists
  # The purpose of this class is to group a collection of UserList with its sorting
  # strategy and list owner, so they can all be passed from the controller down to
  # the view component that will render UserLists::ProfileListsSortingDropdownComponent
  #
  # It should quack like an array of UserList.
  class ListCollection
    include Enumerable

    attr_reader :owner
    attr_reader :sorting_strategy

    def initialize(lists, owner:, sorting_strategy: SortingStrategy.new)
      @lists = sorting_strategy.apply(lists)
      @sorting_strategy = sorting_strategy
      @owner = owner
    end

    def each(&block)
      @lists.each(&block)
    end

    # Makes it Array.wrap()'able
    def to_ary
      @lists.to_ary
    end
  end
end
