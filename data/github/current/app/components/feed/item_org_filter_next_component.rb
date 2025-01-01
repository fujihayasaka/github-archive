# typed: true
# frozen_string_literal: true

module Feed
  class ItemOrgFilterNextComponent < ItemFilterComponent
    attr_reader :user, :org

    GROUP_ICON = ItemFilterComponent::GROUP_ICON.merge({
      "RepositoryActivity" => {
        name: :"repo",
        color: :done
      }
    }).freeze

    GROUP_DETAILS = {
      "Releases" => "Update posts from repositories",
      "Repositories" => "Repositories that are created or forked by people",
      "RepositoryActivity" => "Issues and pull requests from repositories",
    }.freeze

    sig { params(org: String, feed_filter: T.nilable(Conduit::OrgFeedFilter), user: T.nilable(User)).void }
    def initialize(org, feed_filter: nil, user: nil)
      super(feed_filter:, is_topic:, is_org: true)
      @org = org
      @user = user
    end

    # exclude filters w/ feature flags to calculate active filter.
    sig { returns(T::Hash[String, T::Boolean]) }
    def values
      feed_filter.values.slice(*feed_filter.available_groups.keys)
    end

    sig { returns(T::Hash[String, T::Boolean]) }
    def default_values
      feed_filter = Conduit::OrgFeedFilter.new(OrganizationFeedFilterSettings.new.values, viewer: user)
      feed_filter.values.slice(*feed_filter.available_groups.keys)
    end

    sig { returns(T::Array[String]) }
    memoize def item_filter_groups
      feed_filter.available_groups.keys
    end

    sig { params(group_name: String).returns(String) }
    def get_group_details(group_name:)
      GROUP_DETAILS[group_name]
    end
  end
end
