# typed: true
# frozen_string_literal: true

require "monolith-twirp-conduit-feeds"

module Conduit
  ##
  # This class represents the feed filter for a user.
  # It is used to determine which feed items should be shown to the user.

  class OrgFeedFilter
    ##
    # The filter groups for organization feeds are defined here.
    # The group names are defined in ORG_FILTER_GROUPS.
    #
    FILTER_GROUPS = {
      "Releases" => [
        :release_repo
      ],
      "Repositories" => [
        :created_repo,
        :forked_repo,
        :created_pr,
        :closed_pr,
        :reopened_pr,
        :merged_pr_repo,
        :labeled_pr,
        :commented_pr,
        :created_issue,
        :closed_issue,
        :reopened_issue,
        :labeled_issue,
        :commented_issue,
        :private_to_public_repo,
      ],
      "RepositoryActivity" => [
        :member_add_to_repo,
      ],
    }.freeze


    ##
    # This hash maps the Twirp keys to the group names.
    #
    TWIRP_KEY_TO_GROUP = {
      # repositories
      TwirpHelper.forked_repository_key           => "Repositories",
      TwirpHelper.created_repository_key          => "Repositories",
      TwirpHelper.private_to_public_repository_key => "Repositories",
      #repository activity
      TwirpHelper.labeled_issue_key => "RepositoryActivity",
      TwirpHelper.private_to_public_repository_key => "RepositoryActivity",
      TwirpHelper.labeled_pull_request_key        => "RepositoryActivity",
      TwirpHelper.merged_pull_request_key         => "RepositoryActivity",
      TwirpHelper.closed_pull_request_key         => "RepositoryActivity",
      TwirpHelper.created_issue_key               => "RepositoryActivity",
      TwirpHelper.created_pull_request_key        => "RepositoryActivity",
      TwirpHelper.closed_issue_key                => "RepositoryActivity",
      TwirpHelper.reopened_issue_key              => "RepositoryActivity",
      TwirpHelper.reopened_pull_request_key       => "RepositoryActivity",
      TwirpHelper.member_add_to_repository_key    => "RepositoryActivity",
      TwirpHelper.created_pull_request_comment_key => "RepositoryActivity",
      TwirpHelper.created_issue_comment_key       => "RepositoryActivity",
      # releases
      TwirpHelper.published_release_key           => "Releases",
    }

    ##
    # This hash maps the group names to the protobuf event types.
    #
    # @return [Hash] the hash of groups where the values are protobuf event types.
    GROUP_TO_EVENT_TYPES = {
      "Releases": [
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_RELEASE_PUBLISH
      ],
      "Repositories": [
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_REPOSITORY_CREATE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_REPOSITORY_FORK,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_REPOSITORY_VISIBILITY_CHANGE,
      ],
      "RepositoryActivity": [
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_MEMBER_ADD_TO_REPOSITORY,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_CREATE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_CLOSE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_MERGE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_REOPEN,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_LABEL,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_PULL_REQUEST_COMMENT_CREATE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_ISSUE_CREATE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_ISSUE_CLOSE,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_ISSUE_REOPEN,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_ISSUE_LABEL,
        MonolithTwirp::Conduit::Feeds::V1::EventType::EVENT_TYPE_ISSUE_COMMENT_CREATE
      ],
    }

    ##
    # Returns the group name for the given Twirp key.
    #
    # @return [Conduit::OrgFeedFilter::FILTER_GROUPS] the hash of groups.
    def self.all_groups
      FILTER_GROUPS
    end

    ##
    # Validates the group name is part of the FILTER_GROUPS.
    #
    # @param group_name [String] the group name to validate.
    # @return [Boolean] true if the group name is valid.
    def self.is_valid_group?(group_name)
      FILTER_GROUPS.key?(group_name)
    end

    ##
    # Returns a subset of the FILTER_GROUPS based on the viewer's feature flags configuration
    #
    # @param viewer [User] the user to check the feature flags for.
    # @return [Hash] the hash of groups.
    def self.available_groups(viewer:)
      groups = FILTER_GROUPS.dup
      groups.delete("RepositoryActivity") unless GitHub.flipper[:feeds_v2].enabled?(viewer)

      groups
    end

    ##
    # Returns a hash of the filter groups with all values set to true.
    #
    # @return [Hash] the hash of groups where the values are booleans.
    def self.include_all_filter
      FILTER_GROUPS.transform_values { |_v| true }
    end

    ##
    # Returns a hash of the filter groups with all values set to false.
    #
    # @return [Hash] the hash of groups where the values are booleans.
    def self.exclude_all_filter
      FILTER_GROUPS.transform_values { |_v| false }
    end

    ##
    # Returns a hash of the groups available to the user based on their feature flags configuration with all values set to true.
    #
    # @param viewer [User] the user to check the feature flags for.
    # @return [Hash] the hash of groups where the values are booleans.
    def self.include_available_filter(viewer)
      self.available_groups(viewer: viewer).transform_values { |_v| true }
    end
    ##

    ##
    # The constructor for OrgFeedFilter
    #
    # @param filter_values [Hash] the hash of filter values where the keys are the group names and the values are booleans. It could contain either all or a subset of the groups.
    # @param viewer [User] the user to check the feature flags for.
    # @return [void]
    def initialize(filter_values, viewer: nil)
      @viewer = viewer

      available_filters = self.class.include_available_filter(viewer)
      @filter = hydrate_filter(filter_values || available_filters)
    end

    ##
    # Returns a hash of the groups available to the user based on their feature flags configuration.
    # The values are memorized.
    # @return [Hash] the hash of groups where the values are booleans.
    def available_groups
      return @available_groups if defined?(@available_groups)
      @available_groups ||= self.class.available_groups(viewer: @viewer)
    end

    ##
    # Instance method to validate the group name is part of the FILTER_GROUPS.
    #
    # @param group_name [String] the group name to validate.
    # @return [Boolean] true if the group name is valid.
    def is_valid_group(group_name)
      self.class.is_valid_group?(group_name)
    end

    ##
    # Returns a hash of the filter groups where the values are booleans.
    # The values will also be a complete set even if the initialized filter values did not contain all the groups.
    # @return [Hash] the hash of groups where the values are booleans.
    def values
      @filter
    end

    ##
    # Returns an array of group names that are enabled (ie: the value is true).
    #
    # @return [Array] the array of group names.
    def enabled_group_keys
      values.select { |k, v| available_groups[k].present? && v == true }.keys
    end

    ##
    # set the filter to include all groups.
    #
    # @return [Hash] the hash of groups where the values are true
    def include_all!
      @filter = self.class.include_all_filter
    end

    ##
    # set the filter to exclude all groups.
    #
    # @return [Hash] the hash of groups where the values are false
    def exclude_all!
      @filter = self.class.exclude_all_filter
    end

    ##
    # Validates the filter includes all groups.
    #
    # @return [Boolean] true if the filter includes all groups.
    def include_all?
      available_groups.keys.all? { |group_name| @filter[group_name] }
    end

    ##
    # Validates the filter include a group.
    #
    # @param group_name [String] the group name to validate.
    # @return boolean true if the filter includes the group.
    def includes_group?(group_name)
      enabled?(group_name) && available_groups.keys.include?(group_name)
    end

    ##
    # Validates the filter include a group.
    #
    # @param group_name [String] the group name to validate.
    # @return boolean true if the filter includes the group.
    def includes_org_group?(group_name)
      enabled?(group_name) && available_groups.keys.include?(group_name)
    end

    ##
    # Validates the group is enabled.
    # Check if the name is valid and the value is true.
    # @param group_name [String] the group name to validate.
    # @return [Boolean] true if the group is enabled.
    def enabled?(group_name)
      is_valid_group(group_name) && @filter[group_name]
    end

    ##
    # Set the filter to include additional groups.
    #
    # @param groups [Array] the array of group names to include.
    # @return [Hash] The hash of updated filter with the additional groups set to true.
    def with_groups(groups)
      return @filter unless groups

      dup = @filter.dup
      groups.each do |group_name|
        dup[group_name] = true
      end

      dup
    end

    ##
    # Set the filter to exclude groups.
    #
    # @param groups [Array] the array of group names to exclude.
    # @return [Hash] The hash of updated filter with the groups set to false.
    def without_groups(groups)
      return @filter unless groups

      dup = @filter.dup
      groups.each do |group_name|
        dup[group_name] = false
      end

      dup
    end

    ##
    # Validates if the Twirp item is included in the filter.
    #
    # @param item [MonolithTwirp::Conduit::Feeds::V1::FeedItem] the Twirp item to validate.
    # @return [Boolean] true if the item is included in the filter.
    def include_item?(item)
      return false if item.nil?

      if key = TwirpHelper.key_for_item(item)
        return filter_enabled?(key)
      end

      false
    end

    ##
    # Returns the protobuf event types based on the selected filter
    #
    # @return [Array] the array of protobuf event types.
    def event_types
      values
        .select { |_, v| v == true }
        .map { |g, _| GROUP_TO_EVENT_TYPES[g.to_sym] }
        .flatten
        .compact
    end

    private


    ##
    # Hydrates the filter values to include all groups.
    #
    # @param values [Hash] the hash of filter values where the keys are the group names and the values are booleans. It could contain either all or a subset of the groups.
    # @return [Hash] the hash of groups where the values are booleans.
    def hydrate_filter(values)
      all_filter = self.class.exclude_all_filter
      cleaned_values = values.stringify_keys.select { |group| available_groups.keys.include?(group) }

      all_filter.merge(cleaned_values)
    end

    ##
    # Validates if the Twirp key is included in the filter.
    #
    # @param key [String] the Twirp key to validate.
    # @return [Boolean] true if the key is included in the filter.
    def filter_enabled?(key)
      group = TWIRP_KEY_TO_GROUP[key]
      @filter[group] || false
    end
  end
end
