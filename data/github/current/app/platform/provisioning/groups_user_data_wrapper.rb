# typed: true
# frozen_string_literal: true

require "forwardable"

module Platform
  module Provisioning
    class GroupsUserDataWrapper
      extend Forwardable

      def initialize(user_data)
        @user_data = user_data
      end

      # delegate :fetch, :fetch_all, and :delete_if directly to the underlying UserData
      def_delegators :@user_data, :fetch, :fetch_all, :delete_if

      # Public: group attributes can have two different names - `groups` or
      # `http://schemas.microsoft.com/ws/2008/06/identity/claims/groups`
      # get values for both keys and return a combined list
      #
      # Returns: Array of Strings (representing group id's from the UserData)
      def groups
        return [] if @user_data.nil?

        @group_ids ||= groups_attributes.map { |attr| attr["value"] }.compact.uniq
      end

      # Public: return raw UserData entries for all the groups attributes
      #
      # Returns: Array of Value mappings for the groups elements
      # e.g. [{ "name" => "groups", "value" => "github", "metadata" => {} }]
      def groups_attributes
        return [] if @user_data.nil?

        @group_attributes ||= Platform::Provisioning::SamlUserData::GROUP_ATTRIBUTE_NAMES.inject([]) do |groups, key|
          groups.concat(fetch_all(key))
        end
      end

      # Public: Sync the group attributes with the ones in the given list -
      # any groups that are not present in valid_group_ids are removed
      #
      # valid_group_ids - a hash of group id's to keep. The key in the hash is the login of the
      #                   organization and the value is the external_id of its ExternalIdentity.
      #                   If either matches, the attribute is kept
      #
      # Returns: an updated UserData
      def sync_group_attributes(valid_group_ids:)
        ids = (valid_group_ids.keys + valid_group_ids.values).compact.uniq
        delete_if do |attr|
          Platform::Provisioning::SamlUserData::GROUP_ATTRIBUTE_NAMES.include?(attr["name"]) &&
            !ids.include?(attr["value"])
        end
      end
    end
  end
end
