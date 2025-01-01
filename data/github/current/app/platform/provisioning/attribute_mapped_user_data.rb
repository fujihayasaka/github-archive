# typed: false
# frozen_string_literal: true

require "forwardable"

module Platform
  module Provisioning
    class AttributeMappedUserData
      SUPPORTED_ATTRIBUTES = {
        user_name: :single,
        external_id: :single,
        display_name: :single,
        emails: :multiple,
        given_name: :single,
        family_name: :single,
        active: :single,
        ssh_keys: :multiple,
        gpg_keys: :multiple,
        admin: :single,
        groups: :multiple,
        roles: :multiple
      }

      TRUE = "true"

      extend Forwardable

      # delegate methods directly to the underlying UserData
      def_delegators :@user_data,
        :count,
        :each,
        :append,
        :replace,
        :delete,
        :delete_all,
        :delete_if,
        :slice,
        :to_a,
        :map,
        :any?,
        :none?,
        :email,
        :active?,
        :name_id,
        :reduce,
        :name_id_metadata,
        :default_attribute_mapping,
        :as_json,
        :multi_slice,
        :rebuild_contributions,
        :rebuild_contributions=,

      # Public: Defines a reader helper for attributes that return multiple values.
      #
      # method_name   - A name of a method to setup
      #
      # Returns   - An array of values, for example a list of emails
      def self.define_multiple_return_value_method(method_name)
        define_method(method_name) do
          return @user_data.send(method_name) if @user_data.respond_to?(method_name)

          fetch_all(method_name).map { |value| value["value"] }
        end
      end

      # Public: Defines a reader helper for attributes that return a single value.
      #
      # method_name   - A name of a method to setup
      #
      # Returns   - A value for a given attribute
      def self.define_single_return_value_method(name, field: "value", suffix: nil)
        method_name = [name, suffix].compact.join("_")
        define_method(method_name) do
          fetch(name, {})[field]
        end
      end

      private_class_method :define_multiple_return_value_method,
        :define_single_return_value_method

      # Public: Defines a reader helper for easily fetching an attributes
      # value and metadata.
      #
      # Examples
      #
      #   user_data.user_name
      #   #=> "mona.octocat"
      #   user_data.user_name_metadata
      #   #=> {"format" => "…"}
      SUPPORTED_ATTRIBUTES.each do |method_name, type|
        if type == :multiple
          define_multiple_return_value_method(method_name)
        elsif type == :single
          define_single_return_value_method(method_name)
          define_single_return_value_method(method_name, field: "metadata", suffix: "metadata")
        end
      end

      # Public: Initialize an AttributeMappedUserData.
      #
      # user_data  - User Data to wrap, can either be an instance of SCIM or SAML user data
      #              (ScimUserData or SamlUserData).
      # mapping    - mapping hash to setup readers for, also used in a fetch methods.
      #              It is an optional parameter and when not passed the user data will provide one
      def initialize(user_data, mapping: nil)
        @user_data = user_data
        @mapping = merge_with_defaults(mapping: mapping)
      end

      # Public: A fetch method to get the value out of the user data using a provided map
      #
      # name   - Name of the standardized accessor for all user data
      # default - Default value to return
      #
      # Returns - a hash of name/value pair
      def fetch(name, default = nil)
        real_name = @mapping.fetch(name, name)

        # protect from nil
        return default if real_name.nil?

        case real_name
        when String
          # real_name is a string no additional value checks are needed
          return get_interpolated_value(real_name, default)
        when Array
          # it's an array, so need to find first value that is not nil
          real_name.compact.each do |lookup|
            value = get_interpolated_value(lookup)
            return value unless value.nil?
          end
        end

        default
      end

      # Public: A fetch all method to get the value out of the user data using a provided map
      #
      # name   - Name of the standardized accessor for all user data
      #
      # Returns - a array of hashes of name/value pairs
      def fetch_all(name)
        real_name = @mapping.fetch(name, name)

        case real_name
        when String
          # real_name is a string no additional value checks are needed, just return it
          return @user_data.fetch_all(real_name)
        when Array
          # it's an array, so need to find first value that is not nil
          real_name.each do |attr|
            value = @user_data.fetch_all(attr)
            return value unless value.nil? || value.count == 0
          end
        end

        []
      end

      # Public: Convenience helper for fetching 'primary email'.
      #
      # Returns the first email.
      def primary_email
        return @user_data.primary_email if @user_data.respond_to?(:primary_email)

        emails.first
      end

      # Public: Convenience helper for fetching emails linked to an external identity with metadata {primary, type}
      #
      # Returns an array of email hashes
      def emails_with_metadata
        fetch_all(:emails)
      end

      # Public: Merge two hashes and insert mapping values as the first entry in the array
      #
      # Returns merged hash
      def self.merge_with_attribute_maps(default_map:, custom_map:)
        return default_map if custom_map.nil?

        # no need to check if the value is duplicate, just add it in
        default_map.merge(custom_map) do |_key, default_value, custom_value|
          case default_value
          when String
            next custom_value if custom_value == default_value
            [custom_value, default_value]
          when Array
            [custom_value] + default_value
          end
        end
      end

      # Public: Method that will convert the admin attribute to a boolean
      #
      # Returns true when admin flag is set to "true"
      def admin?
        return false if admin.blank?
        admin.downcase == TRUE
      end

      private

      # Private: Merge two hashes and insert mapping values as the first entry in the array
      #
      # Returns merged hash
      def merge_with_defaults(mapping:)
        self.class.merge_with_attribute_maps(
          default_map: @user_data.default_attribute_mapping,
          custom_map: mapping,
        )
      end

      # Private: Evaluate the string values passed in the following format: %{value}.  There can be multiple
      #   values in a string to evaluate.
      #
      # interpolated_mapping - string to evaluate with or without interpolation
      # default - a default value to be passed into a lookup
      #
      # Example of an interpolated string: "%{name.givenName} %{name.familyName}"
      #
      # Returns new string or nil
      def get_interpolated_value(interpolated_mapping, default = nil)
        return @user_data.fetch(interpolated_mapping, default) unless interpolated_mapping.include?("%")

        # create a hash dynamically by getting keys out of the interpolated string below
        # values will be fetched from user data and returned
        hash = Hash.new do |h, key|
          # fetch value from user data
          h[key] = @user_data.fetch(key.to_s, {})["value"].to_s
        end

        mapped_value = interpolated_mapping % hash

        return { "value" => mapped_value } unless mapped_value.strip.blank?
      end
    end
  end
end
