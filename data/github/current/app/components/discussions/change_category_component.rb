# typed: true
# frozen_string_literal: true

module Discussions
  class ChangeCategoryComponent < ApplicationComponent
    delegate :discussions_search_path, to: :helpers
    delegate :repository, :can_update_discussion?, :can_edit_category?, to: :timeline

    sig { params(category: DiscussionCategory, timeline: DiscussionTimeline, org_param: T.nilable(String)).void }
    def initialize(category:, timeline:, org_param: nil)
      @category = category
      @timeline = timeline
      @org_param = org_param
    end

    private

    sig { returns(DiscussionCategory) }
    attr_reader :category

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(T::Boolean) }
    def can_modify_category?
      return false unless user_can_edit_category?

      # Will return false if a category supports polls but is the only poll supporting category in the repo
      # Categories that don't support polls don't need any additional checks
      return true unless category.supports_polls
      repo = Repositories::Public.find_active!(category.repository_id)

      supports_polls_count = repo.discussion_categories.where(supports_polls: true).size
      supports_polls_count > 1
    end

    sig { returns(T::Boolean) }
    def user_can_edit_category?
      can_edit_category?
    end

    def category_emoji
      emoji_tag(emoji_for(category.emoji), class: "f5")
    end
  end
end
