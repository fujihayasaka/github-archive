# typed: true
# frozen_string_literal: true

module Platform
  module Provisioning
    class SCIMGroupData < UserData
      user_data_reader \
        external_id: "externalId",
        display_name: "displayName",
        user_name: "userName"

      # Public: Instantiates a new UserData instance from the provided SCIM input.
      #
      # scim_input - request data represented as a Hash.
      #
      # Returns a SCIMGroupData instance.
      def self.load(scim_input)
        # set the externaId to displayName, if there is no externalId for the group
        external_id = if scim_input["externalId"]
          scim_input["externalId"]
        else
          scim_input["displayName"]
        end

        scim_attrs = [
          # set the userName to displayName, so ExternalIdentity can do uniqueness validation
          { "name" => "userName", "value" => scim_input["displayName"] },
          { "name" => "displayName", "value" => scim_input["displayName"] },
          { "name" => "externalId", "value" => external_id },
        ]

        if scim_input["members"].is_a?(Array)
          scim_attrs += scim_input["members"].map do |member|
            { "name" => "members", "value" => member["value"] }
          end
        end

        new(scim_attrs).replace_all_members(false)
      end

      def members
        fetch_all("members")
      end

      # Public: sets the value to replace all members
      def replace_all_members(value)
        @replace_all_members = value
        self
      end

      def replace_all_members?
        @replace_all_members
      end
    end
  end
end
