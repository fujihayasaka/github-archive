# typed: true
# frozen_string_literal: true

module UserLists
  class ShowComponent < ApplicationComponent
    # list - a UserList
    # page - Integer page number for which page of items in the UserList should be shown
    def initialize(list:, page: 1)
      @list = list
      @page = page
    end

    private

    attr_reader :list, :page

    delegate :cap_filter, to: :helpers

    def mine?
      logged_in? && list.user_id == current_user.id
    end

    memoize def visible_list_item_repositories
      list.item_repositories_visible_to(
        viewer: current_user,
        cap_filter: cap_filter,
      )
    end

    def visible_item_count
      visible_list_item_repositories.size
    end

    def user_list_feed_enabled?
      GitHub.conduit_feed_enabled? && helpers.user_feature_enabled?(:user_list_feed)
    end

    def hide_explore_link?
      GitHub.multi_tenant_enterprise?
    end
  end
end
