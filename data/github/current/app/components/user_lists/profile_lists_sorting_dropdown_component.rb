# typed: true
# frozen_string_literal: true

class UserLists::ProfileListsSortingDropdownComponent < ApplicationComponent
  attr_reader :user_lists

  def initialize(user_lists:)
    @user_lists = user_lists
  end

  def available_strategies
    UserLists::SortingStrategy::STRATEGY_TO_HUMAN_MAP.keys.map do |serialized_strategy|
      UserLists::SortingStrategy.unserialize(serialized_strategy)
    end
  end

  def selected?(strategy)
    strategy.serialize == user_lists.sorting_strategy.serialize
  end

  def strategy_url(strategy)
    # keep page filters applied to stars
    new_params = params.slice(:sort, :direction, :type)
      .merge(tab: "stars", user_lists_sort: strategy.sort_by, user_lists_direction: strategy.direction)

    user_path(user_lists.owner, params: new_params.permit!.to_h)
  end
end
