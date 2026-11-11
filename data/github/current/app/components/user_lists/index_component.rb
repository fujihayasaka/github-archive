# typed: true
# frozen_string_literal: true

class UserLists::IndexComponent < ApplicationComponent
  def initialize(user_lists:, mine:)
    @user_lists = user_lists
    @mine = mine
  end

  private

  delegate :cap_filter, to: :helpers

  memoize def user_lists
    # Prefill HTML names and descriptions efficiently from memcache:
    GitHub::PrefillAssociations.prefill_batch_method(@user_lists, :async_name_html)
    GitHub::PrefillAssociations.prefill_batch_method(@user_lists, :async_description_html)
    @user_lists
  end

  def mine?
    @mine
  end

  def render?
    mine? || user_lists.any?
  end

  memoize def can_create_lists?
    current_user&.can_create_lists?
  end
end
