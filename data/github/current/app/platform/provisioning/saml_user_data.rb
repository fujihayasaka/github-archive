# typed: true
# frozen_string_literal: true

module Platform
  module Provisioning
    class SamlUserData < UserData
      NAME_ID = "NameID"
      DEFAULT_EXPIRY = 65.minutes

      user_data_reader name_id: NAME_ID

      # we will accept group data in attributes with one of these names
      GROUP_ATTRIBUTE_NAMES = [
        # "http://schemas.xmlsoap.org/claims/Group",
        "groups",
        "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups",
      ]

      # For GHES, we don't use any default or fallback logic for the display name attribute.
      # We only use the value that is set in the attribute_mappings of lib/github/authentication/saml.rb
      EMPTY_DISPLAY_NAME_ATTRIBUTE = []

      # Default attribute mappings for display_name for non-GHES environments
      DEFAULT_DISPLAY_NAME_ATTRIBUTE = [
        "http://schemas.microsoft.com/identity/claims/displayname",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "full_name"
      ]

      DEFAULT_USER_NAME_ATTRIBUTE = [
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "username",
      ]

      # This constant contains mappings between method names that will be created on a class and
      # how the values are stored in the attributes.
      # We are storing actual attribute names from a document with their values, this mapping consolidates
      # access to same attributes between SAML and SCIM user data.
      # Most of the time the attribute map will contain a single value for an attribute map, however
      # if an array is present the values in an array provide an override.  First existing attribute value
      # from an array map will be returned.
      #
      # display_name mapping will be added dynamically below in the default_attribute_mapping method
      # due to environment differents.
      #
      # Example:
      #   emails: ["emails", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"]
      #   #=> will check "emails" first and return a value for an attribute if the mapping was found
      #       otherwise if will continue and check "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
      DEFAULT_ATTRIBUTE_MAPPINGS = {
        user_name: DEFAULT_USER_NAME_ATTRIBUTE + [NAME_ID],
        external_id: [
          "http://schemas.microsoft.com/identity/claims/objectidentifier",
          "http://schemas.auth0.com/oid",
          "external_id"
        ],
        emails: [
          "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
          "emails"
        ],
        given_name: [
          "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
          "givenName",
          "given_name"
        ],
        family_name: [
          "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
          "familyName",
          "family_name"
        ],
        active: "http://schemas.auth0.com/account_enabled",
        ssh_keys: "public_keys",
        gpg_keys: "gpg_keys",
        admin: "administrator",
        groups: GROUP_ATTRIBUTE_NAMES,
        roles: "roles"
      }

      # These attributes are considered safe to persist.
      #
      # Unsafe attributes include (temporary) access tokens, unneeded personal
      # data.
      SAFE_LIST = [
        # AzureAD
        "http://schemas.microsoft.com/identity/claims/tenantid",
        "http://schemas.microsoft.com/identity/claims/objectidentifier",
        "http://schemas.microsoft.com/identity/claims/displayname",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
        "http://schemas.auth0.com/oid",
        "http://schemas.auth0.com/account_enabled",

        # Okta
        "external_id",
        "emails",
        "given_name",
        "family_name",
        "full_name",

        # Generic
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
        "givenName",
        "familyName",

        # Groups
        GROUP_ATTRIBUTE_NAMES,

        # roles
        "roles"
      ].flatten

      # Public: Instantiates a new UserData instance from the provided
      # SAML response.
      #
      # saml_assertion        - A SAML::Message::Response object containing the user data.
      # attribute_mapping     - a hash containing mapping of attributes, readers will be generated for
      # configurable_attrs    - An optional array of attributes from the Assertion to persist.
      #                           These can be configured by the administrator for Enterprise Server
      #
      # Returns a AttributeMappedUserData
      def self.load(saml_assertion, attribute_mapping: nil, persist_attributes: false, configurable_attrs: [])
        ret_user_data = self.new.tap do |user_data|
          user_data.append NAME_ID, saml_assertion.name_id,
            "Format" => saml_assertion.name_id_format if saml_assertion.name_id

          if persist_attributes
            saml_assertion.attributes.each do |key, values|
              next unless SAFE_LIST.include?(key) || configurable_attrs.include?(key)
              values.each do |value|
                user_data.append key, value
              end
            end
          end
        end

        Platform::Provisioning::AttributeMappedUserData.new(ret_user_data, mapping: attribute_mapping)
      end

      # Public: returns the true parameter.
      def active?
        true
      end

      # Public: Provides the default mapping for user data
      #
      # Returns a hash of default mappings for user data
      def default_attribute_mapping
        DEFAULT_ATTRIBUTE_MAPPINGS.merge(
          display_name:
            if GitHub.saml_display_name_default_attribute_mapping_disabled?
              EMPTY_DISPLAY_NAME_ATTRIBUTE
            else
              DEFAULT_DISPLAY_NAME_ATTRIBUTE
            end
        )
      end

      # Public: finds a slice of the first key that is passed
      #
      # Attribute slice of user data
      def multi_slice(keys)
        keys.each do |key|
          data = slice(key)
          return data if data.any?
        end
      end

      # Public: Stores the user data in a persistent store to be retrieved
      # after user completes GitHub sign-in
      #
      # Returns String
      def self.persist(user_data, target: nil)
        key = "saml-user-data:#{SecureRandom.hex(16)}"
        save_key = "#{target.class.name}-#{target.id}-#{key}"
        json = user_data.to_json
        persistent_store(target: target).set(save_key, json, expires: DEFAULT_EXPIRY.from_now)
        key
      end

      # Public: Retrieves SAML user data associated with the session to complete SSO
      #
      # Returns a AttributeMappedUserData
      def self.get(key, target: nil)
        get_key = "#{target.class.name}-#{target.id}-#{key}"
        json = persistent_store(target: target).get(get_key).value { nil } || ""

        return if json.size == 0

        use_data_array = begin
          JSON.parse(json)
        rescue JSON::ParserError
          []
        end

        user_data = Platform::Provisioning::SamlUserData.new(use_data_array)
        Platform::Provisioning::AttributeMappedUserData.new(user_data)
      end

      def self.persistent_store(target: nil)
        ExternalIdentities::KV
      end
    end
  end
end
