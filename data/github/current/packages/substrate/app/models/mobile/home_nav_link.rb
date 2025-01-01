# typed: true
# frozen_string_literal: true

module Mobile
  # Public: Represents a sortable, hideable user dashboard navigation link including
  # class level methods for storing and retrieving links for a specific user.
  #
  # Data is stored in GitHub::KV and mapped from identifier strings to ints using
  # the ALL_LINKS, DOTCOM_LINKS, and ENTERPRISE_LINKS constants.
  class HomeNavLink
    # Enum mapping defining values stored in GitHub::KV. Outside of this class
    # all identifier values are the keys of this constant. Starts at 1 to avoid
    # nil.to_i coercing to 0.
    #
    # Do not modify order or change values without providing a mechanism to safely
    # read previously written data. New values can be safely appended.
    ALL_LINKS = {
      "issues"        => 1,
      "pull_requests" => 2,
      "discussions"   => 3,
      "projects"      => 7,
      "repositories"  => 4,
      "organizations" => 5,
      "starred"       => 6
    }.freeze

    DOTCOM_LINKS = ALL_LINKS
    DOTCOM_LINKS_INVERTED = DOTCOM_LINKS.invert.freeze

    # Link identifiers that will be hidden/dropped in enterprise environments.
    ENTERPRISE_EXCLUSIONS = %w(projects).freeze

    ENTERPRISE_LINKS = ALL_LINKS.except(*ENTERPRISE_EXCLUSIONS).freeze
    ENTERPRISE_LINKS_INVERTED = ENTERPRISE_LINKS.invert.freeze

    STORE_KEY_PREFIX = "dashnavlinks".freeze
    STORE_KEY_VERSION = 1

    def self.links_map
      if GitHub.enterprise?
        ENTERPRISE_LINKS
      else
        DOTCOM_LINKS
      end
    end

    def self.links_map_inverted
      if GitHub.enterprise?
        ENTERPRISE_LINKS_INVERTED
      else
        DOTCOM_LINKS_INVERTED
      end
    end

    # Uses the Platform KV loader to retrieve all links for a user from GitHub::KV.
    #
    # user - The user to retrieve links for.
    #
    # Returns a Promise of an Array of NavLink objects.
    def self.async_all_for_user(user)
      key = store_key_for_user(user)

      Platform::Loaders::KV.load(key).then do |value|
        links_from_raw_value(value)
      end
    end

    # Retrieves all links for a user from GitHub::KV or returns the default links.
    #
    # user - The user to retrieve links for.
    #
    # Returns an array of NavLink objects.
    def self.all_for_user(user)
      key = store_key_for_user(user)

      value = begin
        GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
      rescue GitHub::KV::UnavailableError
        nil
      end

      links_from_raw_value(value)
    end

    # Builds a list of NavLink objects from a String retrieved from GitHub::KV.
    # See the update_for_user! method for details on the string format. Removes
    # any links without a matching identifier in the links_map value. Appends
    # any possibly missing links to the end of the output to facilitate adding
    # new links in the future.
    #
    # value - The String retrieved from GitHub::KV.
    #
    # Returns an array of NavLink objects.
    def self.links_from_raw_value(value)
      return default_links if value.blank?

      # Unknown link identifiers retrieved from storage are skipped.
      links = value.split(",").uniq.map! do |link_str|
        identifier_int, hidden_int = link_str.split(":", 2).map(&:to_i)
        next unless identifier = links_map_inverted[identifier_int]
        hidden = !hidden_int.zero?
        new(identifier: identifier, enum_value: identifier_int, hidden: hidden)
      end.compact

      # New link identifiers that are not in the stored value are appended to the end.
      if links.count < links_map.count
        missing_links = (links_map.keys - links.map(&:identifier)).map do |missing_identifier|
          new(identifier: missing_identifier, enum_value: links_map[missing_identifier], hidden: false)
        end

        links.concat(missing_links)
      end

      links
    end

    # Update the order and hidden status of the nav links for a user.
    #
    # Data is stored in GitHub::KV as comma delimited pairs of integers.
    # The first digit representing the identifier of the link, and the second
    # digit being the hidden status of the link. Pairs are separated by a
    # colon.
    #
    # The value "0:0,1:0,2:0,3:0,4:0" represents 5 non-hidden links. The integer
    # identifer values are mapped to human readable values in the links_map value.
    #
    # user - The user to update stored nav link configuration for.
    # sorted_links - An Array of link identifier strings to store in sorted order.
    # hidden_links - An Array of link identifier strings to flag as hidden.
    #
    # Returns the result of calling GitHub.kv.set.
    def self.update_for_user!(user, sorted_links:, hidden_links: [])
      nav_objects = Array.wrap(sorted_links).uniq.map do |identifier|
        next unless links_map.key?(identifier)
        new(identifier: identifier, enum_value: links_map[identifier], hidden: hidden_links.include?(identifier))
      end.compact

      key = store_key_for_user(user)
      value = nav_objects.map(&:to_kv_value).join(",")

      GitHub.kv.set(key, value) # rubocop:todo GitHub/DoNotUseGlobalKv

      GitHub.instrument("user_dashboard.nav_links_update", {
        user: user,
        user_dashboard_links: value
      })

      links_from_raw_value(value)
    end

    # The key for storing the nav link values for a user in GitHub::KV.
    #
    # user - The user this key belongs to.
    # version - A version value to include in the key, optional and defaults to the STORE_KEY_VERSION constant.
    # prefix - The prefix for all storage keys, optional and defaults to the STORE_KEY_PREFIX constant.
    #
    # Returns a String.
    def self.store_key_for_user(user, version: STORE_KEY_VERSION, prefix: STORE_KEY_PREFIX)
      "#{prefix}:#{version}:#{user.id}"
    end

    # Constructs a default set of links. Used in cases where data is unreadable
    # or the user has no previous value stored in GitHub::KV.
    #
    # Returns an array of NavLink objects.
    def self.default_links
      links_map.map do |identifier, enum_value|
        new(identifier: identifier, enum_value: enum_value, hidden: false)
      end
    end

    attr_reader :identifier, :enum_value, :hidden

    # Initialize a NavLink.
    #
    # identifier - The identifier for this link, expects a key from the links_map value.
    # hidden - Whether this link is hidden or not, optional and defaults to false.
    #
    # Returns a NavLink object.
    def initialize(identifier:, enum_value:, hidden: false)
      @identifier = identifier
      @enum_value = enum_value
      @hidden = hidden
    end

    # Whether this NavLink is hidden or not.
    def hidden?
      !!hidden
    end

    # Convert this link into a key-value pair for storage.
    #
    # Returns a String like "2:0".
    def to_kv_value
      "#{enum_value}:#{hidden? ? 1 : 0}"
    end

    def ==(other)
      @identifier == other.identifier &&
        @enum_value == other.enum_value &&
        @hidden == other.hidden
    end

    def attributes
      {
        identifier: identifier,
        enum_value: enum_value,
        hidden: hidden?
      }
    end

    alias_method :to_h, :attributes
  end
end
