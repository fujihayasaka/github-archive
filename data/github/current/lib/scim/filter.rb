# typed: true
# frozen_string_literal: true

module SCIM
  module Filter
    class InvalidFilterError < StandardError
      def message
        "Only single 'eq' operators are supported."
      end
    end

    INTERNAL_ID_ATTRIBUTE = "id".freeze
    USER_NAME_ATTRIBUTE = "userName".freeze
    EXTERNAL_ID_ATTRIBUTE = "externalId".freeze
    DISPLAY_NAME_ATTRIBUTE = "displayName".freeze

    # Internal: Pattern used for single attribute equal queries.
    #
    # http://rubular.com/r/2x14s33IFQ
    #
    # Example usage:
    #
    #   EQ_FILTER_REGEX.match('userName eq "hubot"')
    #   # => #<MatchData name:"userName" value:"hubot">
    EQ_FILTER_REGEX = %r{
      \A                # Beginning of string
      (?<name>\w+)      # [:name] Attribute name (any word character)
      \seq\s            # Equal operator
      "                 # Open quote
      (?<value>[^"]+)   # [:value] Attribute value (anything but a close quote)
      "                 # Close quote
      \z                # End of string
    }xi                 # x: ignore whitepace, i: ignore case

    # Public: Takes a SCIM filter and applies its conditions to the specified
    # ExternalIdentity or ExternalGroup scope.
    #
    # Currently we only support single conditions using the equal operator.
    # If the passed filter is not supported, a 'none' scope will be returned.
    #
    # filter       - The String SCIM filter
    # target_class - a type of query to run, can be ExternalIdentity or ExternalGroup
    # scope        - (Optional) The scoped ExternalIdentity or ExternalGroup relation to apply
    #                the filter to.
    #
    # Returns a scoped ExternalIdentity relation.
    def self.apply(filter, target_class, scope: ExternalIdentity.scoped)
      name, value = parse_eq_filter(filter)
      raise InvalidFilterError unless name && value

      # using scope.first.is_a?(ExternalIdentity) executed a query using type will only
      # create the object in memory and check it's type, saving a query to the database
      if target_class.new.is_a?(ExternalIdentity)
        # Filters can either be on IdP provided attributes or an internal
        # identifier we gave the SCIM client during provisioning. In our
        # case, we use the identity's guid as our internal identifier.
        if name == INTERNAL_ID_ATTRIBUTE
          scope.where(guid: value)
        elsif name == EXTERNAL_ID_ATTRIBUTE
          scope.where(external_id: value)
        elsif name == USER_NAME_ATTRIBUTE
          scope.where(user_name: value)
        else
          user_data = Platform::Provisioning::UserData.new
          user_data.append(name, value)

          scope.by_scim_user_data(user_data)
        end
        # the only other scope that uses this filter is ExternalGroup
        # that is why there is no check here
      else
        # Filters can either be on IdP provided attributes or an internal
        # identifier we gave the SCIM client during provisioning. In our
        # case, we use the groups's guid as our internal identifier.
        if name == INTERNAL_ID_ATTRIBUTE
          scope.where(guid: value)
        elsif name == EXTERNAL_ID_ATTRIBUTE
          scope.where(external_id: value)
        elsif name == DISPLAY_NAME_ATTRIBUTE
          scope.where(display_name: value)
        end
      end
    end

    # Internal: Extracts attribute name and value to filter on from a SCIM
    # string. If filter is not a simple equals query, nothing will be returned.
    #
    # Examples:
    #
    #   parse_eq_filter('userName eq "hubot"')
    #   # => [ "userName", "hubot" ]
    #
    #   parse_eq_filter('userName eq "hubot" and emails eq "hubot@github.com"')
    #   # => nil
    #
    #   parse_eq_filter('emails co "hubot"')
    #   # => nil
    #
    # Returns a Array containing parsed name and value if matched or nothing.
    def self.parse_eq_filter(filter)
      match = EQ_FILTER_REGEX.match(filter)
      match && [match[:name], match[:value]]
    end

  end
end
