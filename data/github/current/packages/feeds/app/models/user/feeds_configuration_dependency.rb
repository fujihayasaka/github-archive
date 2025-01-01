# typed: false
# frozen_string_literal: true

module User::FeedsConfigurationDependency
  extend ActiveSupport::Concern

  FEED_FILTER_SETTINGS_KEY = :user_feed_filter_setting

  included do
    has_one :for_you_feed_filter_settings, class_name: "ForYouFeedFilterSettings", foreign_key: :user_id, inverse_of: :user
    has_one :feed_filter_settings, class_name: "FeedFilterSettings", foreign_key: :user_id, inverse_of: :user
    has_one :organization_feed_filter_settings, class_name: "OrganizationFeedFilterSettings", foreign_key: :user_id, inverse_of: :user
  end

  def set_for_you_feed_filter!(filter_values)
    filter_settings = {
      user_id: self.id
    }

    filter = Conduit::FeedFilter.new(filter_values, viewer: self)
    # groups available via feature flags
    Conduit::FeedFilter.all_groups
      .keys.each do |group_name|
      filter_settings["#{group_name.underscore}_enabled"] = filter.includes_group?(group_name)
    end

    ForYouFeedFilterSettings.upsert(filter_settings)
  end

  def set_feed_filter!(is_topic, filter_values)
    filter_settings = {
      user_id: self.id,
      is_topic: is_topic,
    }

    filter = Conduit::FeedFilter.new(filter_values, viewer: self)
    # groups available via feature flags
    Conduit::FeedFilter.all_groups
      .keys
      .filter { |k| k != "StarredRelationships" }
      .each do |group_name|
      filter_settings["#{group_name.underscore}_enabled"] = filter.includes_group?(group_name)
    end

    begin
      settings = FeedFilterSettings.retry_on_find_or_create_error do
        FeedFilterSettings.find_by(user_id: self.id, is_topic: is_topic) || FeedFilterSettings.new(user_id: self.id, is_topic: is_topic)
      end
      settings.update!(filter_settings)
    rescue ActiveRecord::RecordNotUnique => e
      { id: self.id, created: false, reason: e.message }
    else
      { id: self.id, created: true, reason: "" }
    end
  end

  def set_org_feed_filter!(is_org, filter_values)
    filter_settings = {
      user_id: self.id,
    }

    filter = Conduit::OrgFeedFilter.new(filter_values, viewer: self)
    # groups available via feature flags
    Conduit::OrgFeedFilter.all_groups.keys.each do |group_name|
      filter_settings["#{group_name.underscore}_enabled"] = filter.includes_group?(group_name)
    end

    begin
      settings = OrganizationFeedFilterSettings.retry_on_find_or_create_error do
        OrganizationFeedFilterSettings.find_by(user_id: self.id) || OrganizationFeedFilterSettings.new(user_id: self.id)
      end
      settings.update!(filter_settings)
    rescue ActiveRecord::RecordNotUnique => e
      { id: self.id, created: false, reason: e.message }
    else
      { id: self.id, created: true, reason: "" }
    end
  end
end
