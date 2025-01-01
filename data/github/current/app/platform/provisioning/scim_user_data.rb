# typed: false
# frozen_string_literal: true

module Platform
  module Provisioning
    class ScimUserData < UserData
      EMAILS = "emails"
      GROUPS = "groups"
      ROLES = "roles"
      VALUE = "value"
      NAME = "name"
      METADATA = "metadata"
      PRIMARY = "primary"
      TRUE = "true"
      USER_NAME = "userName"
      ACTIVE = "active"

      # This constant contains mappings between method names that will be created on a class and
      # how the values are stored in the attributes.
      # We are storing actual attribute names from a document with their values, this mapping consolidates
      # access to same attributes between SAML and SCIM user data.
      # Most of the time the attribute map will contain a single value for an attribute map, however
      # if an array is present the values in an array provide an override.  First existing attribute value
      # from an array map will be returned.
      #
      # Example:
      #   display_name: ["displayName", "name.formatted", "userName"]
      #   #=> will check "displayName" first and return a value for an attribute if the mapping was found
      #       otherwise if will continue and check "name.formatted" and "userName" next
      DEFAULT_ATTRIBUTE_MAPPINGS = {
        user_name: "userName",
        external_id: "externalId",
        display_name: ["displayName", "name.formatted", "%{name.givenName} %{name.familyName}", "userName"],
        given_name: "name.givenName",
        family_name: "name.familyName",
        active: "active",
        ssh_keys: "public_keys",
        gpg_keys: "gpg_keys",
        admin: "administrator",
        groups: "groups",
        emails: "emails",
        roles: "roles"
      }

      ATTR_SPLIT_CHAR = "."

      # A definition of attributes that are multi-valued.  The attribute_as_json method will check
      # this hash and return an array of values for example emails will be returned as:
      #
      # { "emails" => [{ "value"=>"okta.octocat@okta.example.com", "primary"=>true, "type"=>"work" }] }
      #
      # Nested attributes are also supported by providing a '.' in the name similar to name.formatted
      ARRAY_ATTRIBUTES = Set[GROUPS, EMAILS, ROLES]

      # Public: Instantiates a new UserData instance from the provided
      # SCIM.
      #
      # input - request data represented as a Hash.
      # attribute_mapping - a hash containing mapping of attributes, readers will be generated for
      #
      # Returns a AttributeMappedUserData
      def self.load(input, attribute_mapping: nil)
        attrs = get_mapped_attributes(input, attribute_mapping)

        has_error = false
        attrs += Array(input[EMAILS]).map do |email|
          case email
          when Hash
            { NAME => EMAILS, VALUE => email[VALUE], METADATA => email.except(VALUE) }
          else
            has_error = true
            next
          end
        end

        attrs += Array(input[GROUPS]).map do |group|
          case group
          when Hash
            { NAME => GROUPS, VALUE => group[VALUE] }
          else
            has_error = true
            next
          end
        end

        attrs += Array(input[ROLES]).filter_map do |role|
          case role
          when Hash
            { NAME => ROLES, VALUE => role[VALUE], METADATA => role.except(VALUE) } if role[VALUE]
          else
            has_error = true
            next
          end
        end

        # return nil, needs to be checked and returned as 400 (Bad Request)
        # when an error was encountered
        return nil if has_error
        Platform::Provisioning::AttributeMappedUserData.new(new(attrs), mapping: attribute_mapping)
      end

      # Public: An override for a name_id to match SAML usr data
      #
      # Returns nothing
      def name_id
        nil
      end

      # Public: Convenience helper for fetching the SCIM 'emails'.
      #
      # Returns an array of emails.
      def emails
        user_name = fetch(USER_NAME, {})[VALUE]
        email_values = fetch_all(EMAILS).map { |email| email[VALUE] }
        if email_values.empty? && user_name&.match(User::EMAIL_REGEX)
          email_values = [user_name]
        end

        email_values
      end

      # Public: Convenience helper for fetching the SCIM 'primary email'.
      #
      # Returns the first primary email.
      def primary_email
        email = fetch_all(EMAILS).detect do |email|
          next unless email && email[METADATA]
          email[METADATA][PRIMARY]
        end
        email.try(:[], VALUE)
      end

      # Public: returns an email address: either primary email, or the first email,
      # or the userName (if it's in the format of an email)
      #
      # Returns a String (or nil).
      def email
        email_value = primary_email || emails.first
        return email_value unless email_value.nil?

        user_name = fetch(USER_NAME, {})[VALUE]
        return user_name if user_name&.match(User::EMAIL_REGEX)

        nil
      end

      # Public: Convenience helper for fetching the SCIM 'roles'.
      #
      # Returns an array of roles.
      def roles
        role_values = fetch_all(ROLES).map { |role| role[VALUE] }
        role_values
      end

      ACTIVE_TRUE = { NAME => ACTIVE, VALUE => TRUE }
      # Public: returns the SCIM 'active' parameter. If missing, returns true
      # since IdPs don't set this by default.
      def active?
        fetch(ACTIVE, ACTIVE_TRUE)[VALUE].downcase == TRUE
      end

      # Public: Provides the default mapping for user data
      #
      # Returns a hash of default mappings for user data
      def default_attribute_mapping
        DEFAULT_ATTRIBUTE_MAPPINGS
      end

      # Public: Returns a hash of all attributes for conversion to json or nil
      #   if user data does not support it.
      #
      # skip_groups   - skips adding groups when set to true
      #
      # Returns a hash of all SCIM attributes
      def as_json(options = nil)
        skip_groups = !options.nil? && options.fetch(:skip_groups, false)

        # setup default complex and multi-value attributes
        json = {
          EMAILS => [],
          ROLES => [],
        }
        json[GROUPS] = [] unless skip_groups

        # loop through each attribute and assign it to the named value
        each do |attr|
          name = attr[NAME]

          # skip groups if skip_groups true
          next if name == GROUPS && skip_groups

          case
          # multi-valued attributes
          when ARRAY_ATTRIBUTES.include?(name)
            value = attribute_as_json(attr, name: VALUE)
            json[name] << value

          # complex value
          when name.include?(ATTR_SPLIT_CHAR)
            name, sub_name = name.split(ATTR_SPLIT_CHAR, 2)
            json[name] = {} if json[name].nil?
            value = attribute_as_json(attr, name: sub_name)
            json[name].merge!(value)

          # simple value
          else
            json[name] = attribute_as_json(attr)
          end
        end

        json
      end

      # Private: Gets the array of name/values pairs from scim data based on the
      #  attribute mappings
      #
      # Returns the array of name/value pairs
      def self.get_mapped_attributes(input, attribute_mapping)
        # merge both maps if custom attribute map was provided
        mapping = Platform::Provisioning::AttributeMappedUserData.merge_with_attribute_maps(\
          default_map: DEFAULT_ATTRIBUTE_MAPPINGS,
          custom_map: attribute_mapping
        )

        attrs_hash = {}
        # loop through all of the mapped attributes
        mapping.values.each do |attr_name|
          # skip emails and groups since those are added manually
          next if ARRAY_ATTRIBUTES.include?(attr_name)

          Array(attr_name).each do |attr|
            attrs_hash[attr] ||= get_attribute(input, attr)
          end
        end

        attrs_hash.values.compact
      end

      # Private: Gets the value of an attribute from scim json (hash).  THe attribute
      #   name can be a single attribute or a nested one separated by ".".
      #
      # Attribute example: userName, name.firstName
      #
      # Returns the value of a scim attribute or nil
      def self.get_attribute(input, attr_name)
        # no value to check just skip it
        return nil if attr_name.nil?

        # split values on "."
        value = input.dig(*attr_name.split(ATTR_SPLIT_CHAR))

        # value was not found return nil
        return if value.nil?

        # return the value
        { NAME => attr_name, VALUE => value.to_s }
      end

      private_class_method :get_mapped_attributes,
        :get_attribute

      private

      # Private: Returns a hash for an attribute.  The hash will only contain a single value attribute.
      #  For example:
      #
      # { "userName" => "okta.octocat@okta.example.com" }
      # { "name" => { "familyName"=>"Octocat" } }
      # { "emails" => [{ "value"=>"okta.octocat@okta.example.com", "primary"=>true, "type"=>"work" }] }
      #
      # Returns a hash for an attribute
      def attribute_as_json(attr, name: nil)
        if name.present?
          # set name if given
          value = {
            name => attr[VALUE]
          }
        else
          value = attr[VALUE]
        end

        # set metadata
        if metadata = attr[METADATA].presence
          value.merge!(metadata)
        end

        value
      end

      # Private: Check if the attribute is an array
      #
      # attr_names - an array of attribute names
      # position - current position within the array
      #
      # Returns true if an attribute is represented as an array in json
      def array_attribute?(attr_names, position)
        attr_name = attr_names.slice(0, position).join(ATTR_SPLIT_CHAR)
        ARRAY_ATTRIBUTES.include?(attr_name)
      end
    end
  end
end
