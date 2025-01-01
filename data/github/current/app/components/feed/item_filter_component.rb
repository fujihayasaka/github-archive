# typed: true
# frozen_string_literal: true

module Feed
  class ItemFilterComponent < ApplicationComponent
    GROUP_ICON = {
      "Announcements" => {
        name: :megaphone,
        color: :done
      },
      "Releases" => {
        name: :tag,
        color: :success
      },
      "Sponsors" => {
        name: :heart,
        color: :sponsors
      },
      "Stars" => {
        name: :star,
        color: :attention
      },
      "Follows" => {
        name: :"person-add",
        color: :accent
      },
      "Repositories" => {
        name: :repo,
        color: :default
      },
      "Recommendations" => {
        name: :"mark-github",
        color: :default
      }
    }

    def initialize(feed_filter: nil, is_topic: false, is_org: false, **sys_args)
      @feed_filter = feed_filter
      @sys_args = sys_args
      @is_topic = is_topic
      @is_org = is_org
    end

    def render?
      feed_filter.present?
    end

    attr_reader :feed_filter, :sys_args, :is_topic, :is_org

    memoize def item_filter_groups
      feed_filter.available_groups.keys.select { |group_name| %w[RepositoryActivity StarredRelationships].exclude?(group_name) }
    end

    def button_hydro_data
      helpers.feed_clicks_hydro_attrs(click_target: "filter_button", metadata: {
        filter_groups: feed_filter&.enabled_group_keys.to_s,
      })
    end

    def filter_title
      if is_topic
        "Topic feed filters"
      else
        if is_org
          "Organization feed filters"
        else
          "Filter"
        end
      end
    end
  end
end
