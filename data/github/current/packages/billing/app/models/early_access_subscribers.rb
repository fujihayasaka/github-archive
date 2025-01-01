# typed: true
# frozen_string_literal: true

#
# Standalone component for wrapping KV access to a list of subscribers who
# wish to be notified when a given organization has been onboarded to a given
# feature
#
# WARNING:
#
# This is a temporary solution for Universe to provide something that should be supported out of the box with
# EarlyAccessMembership but for now we're filling in this gap.
#
# This will be removed once the Tasklist and Roadmap signup page is removed, and should not be relied upon
# by other teams.
#
class EarlyAccessSubscribers

  #
  # Retrieve the given list of subscribers associated with a specific feature and member
  #
  # @param feature_slug [String] the feature slug (from EarlyAccessMembership)
  # @param member_id [Integer] the member identifier (from EarlyAccessMembership)
  #
  def self.get_subscriber_ids(feature_slug, member_id)
    json_value = Billing::Kv.store.get(cache_key(feature_slug, member_id)).value { nil }
    if json_value.nil?
      return []
    end

    begin
      JSON.parse(json_value)
    rescue JSON::ParserError
      GitHub.logger.info(
        "unable to parse value stored in Billing::Kv, falling back to empty id",
        "code.namespace" => "EarlyAccessSubscribers",
        "code.function" => "get_subscriber_ids",
        "gh.early_access_subscribers.get_subscriber_ids.result" => "failed",
        "gh.early_access_subscribers.get_subscriber_ids.member_id" => member_id,
        "gh.early_access_subscribers.get_subscriber_ids.value" => json_value
      )
      []
    end
  end

  #
  # Add a subscriber to the list of subscribers associated with a specific feature and member
  #
  # @param feature_slug [String] the feature slug (from EarlyAccessMembership)
  # @param member_id [Integer] the member identifier (from EarlyAccessMembership)
  # @param actor_id [Integer] an actor to add to the list of subscribers
  #
  def self.append_subscriber_id(feature_slug, member_id, actor_id)
    users_for_org = get_subscriber_ids(feature_slug, member_id)
    users_for_org << actor_id
    Billing::Kv.store.set(cache_key(feature_slug, member_id), users_for_org.uniq.to_json)
  end

  # Helper function for generating the key for a given feature and member pair
  def self.cache_key(feature_slug, member_id)
    "early_access_subscribers:#{feature_slug}:#{member_id}"
  end
end
