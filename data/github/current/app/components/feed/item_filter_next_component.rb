# typed: true
# frozen_string_literal: true

module Feed
  class ItemFilterNextComponent < ApplicationComponent
    attr_reader :user, :feed_filter, :is_topic, :is_org

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
      },
      "RepositoryActivity" => {
        name: :"repo",
        color: :done
      }
    }.freeze

    GROUP_DETAILS = {
      "Announcements" => "Special discussion posts from repositories",
      "Releases" => "Update posts from repositories",
      "Sponsors" => "Relevant projects or people that are being sponsored",
      "Stars" => "Repositories being starred by people",
      "Follows" => "Who people are following",
      "Repositories" => "Repositories that are created or forked by people",
      "RepositoryActivity" => "Issues and pull requests from repositories",
      "Recommendations" => "Repositories and people you may like",
      "StarredRelationships" => "By default, the feed shows events from repositories you sponsor or watch, and people you follow.",
    }.freeze

    sig { params(feed_filter: T.nilable(Conduit::FeedFilter), user: T.nilable(User), is_topic: T::Boolean, is_org: T::Boolean).void }
    def initialize(feed_filter: nil, user: nil, is_topic: false, is_org: false)
      @feed_filter = feed_filter
      @is_topic = is_topic
      @user = user
      @is_org = is_org
    end

    def render?
      feed_filter.present?
    end

    # exclude filters w/ feature flags to calculate active filter.
    sig { returns(T::Hash[String, T::Boolean]) }
    def values
      feed_filter.values.slice(*feed_filter.available_groups.keys)
    end

    sig { returns(T::Hash[String, T::Boolean]) }
    def default_values
      feed_filter = Conduit::FeedFilter.new(ForYouFeedFilterSettings.new.values, viewer: user)
      feed_filter.values.slice(*feed_filter.available_groups.keys)
    end

    sig { returns(T::Array[String]) }
    memoize def item_filter_groups
      feed_filter.available_groups.keys.filter { |group_name| ["StarredRelationships"].exclude?(group_name) }
    end

    sig { params(group_name: String).returns(String) }
    def get_group_details(group_name:)
      GROUP_DETAILS[group_name]
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
