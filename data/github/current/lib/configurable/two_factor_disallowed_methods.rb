# typed: true
# frozen_string_literal: true

module Configurable
  module TwoFactorDisallowedMethods
    include Instrumentation::Model
    extend Configurable::Async
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "two_factor.disallowed_methods".freeze
    FILTER_BATCH_SIZE = 10000

    class InvalidTwoFactorMethod < StandardError; end

    # Store as powers of 2 so we can have a single table value that stores lots of info and use bitwise operations to retrieve
    METHODS_VALUES = {
      insecure: 1,
      sms: 2,
      totp: 4,
      gh_mobile: 8,
      security_key: 16,
      passkey: 32
    }.freeze

    INSECURE = :insecure
    INSECURE_METHODS = Set.new([:sms]).freeze

    # Public: The types of 2FA methods that this entity's member users may not use
    #
    # Returns a collection of 2FA methods
    def get_two_factor_disallowed_methods
      return Set.new unless config.enabled?(Configurable::TwoFactorRequired::KEY)

      get_two_factor_disallowed_methods!
    end

    async_configurable :get_two_factor_disallowed_methods

    # Public: The types of 2FA methods that this entity has configured for diallowing
    # This method ignores any validation checks when querying (like if 2FA in general is required)
    #
    # Returns a collection of 2FA methods
    def get_two_factor_disallowed_methods!
      PrivateMethodOperators.methods_from_raw_value(raw_two_factor_disallowed)
    end

    async_configurable :get_two_factor_disallowed_methods!

    # used for CAP filtering to reduce the queries we make to the configuration_entries table
    # note - considered using the `Configurable.preload_configuration` method instead of implementing this, but that method is a bit more generalized and would have resulted in more queries
    sig { params(businesses: T::Array[Business]).returns(T::Hash[Business, T::Set[Symbol]]) }
    def self.filter_businesses_with_two_factor_disallowed_methods(businesses)
      return Hash.new if businesses.empty?
      businesses.each_slice(FILTER_BATCH_SIZE).with_object(Hash.new) do |slice, memo|
        memo.merge!(filter_businesses_with_two_factor_disallowed_methods_unbatched(slice))
      end
    end

    # used for CAP filtering to reduce the queries we make to the configuration_entries table
    # note - considered using the `Configurable.preload_configuration` method instead of implementing this, but that method is a bit more generalized and would have resulted in more queries
    sig { params(organizations: T::Array[Organization]).returns(T::Hash[Organization, T::Set[Symbol]]) }
    def self.filter_organizations_with_two_factor_disallowed_methods(organizations)
      return Hash.new if organizations.empty?
      organizations.each_slice(FILTER_BATCH_SIZE).with_object(Hash.new) do |slice, memo|
        memo.merge!(filter_organizations_with_two_factor_disallowed_methods_unbatched(slice))
      end
    end

    # Public: The types of 2FA methods that this entity's member users may use
    #
    # Returns a collection of 2FA methods
    def get_two_factor_allowed_methods
      # insecure == SMS - so we want to remove it from the list of all 2FA methods
      all_methods = Set.new(METHODS_VALUES.keys - [:insecure])
      # All methods should be returned if the org/business 2FA requirement is disabled
      return all_methods unless config.enabled?(Configurable::TwoFactorRequired::KEY)

      all_methods - get_two_factor_disallowed_methods
    end

    # Public: Whether insecure 2FA methods are disallowed for this entity's member users
    #
    # Returns a boolean
    def insecure_two_factor_methods_disallowed?
      return false unless invalid_two_factor_methods_available?
      get_two_factor_disallowed_methods.superset? Set.new(INSECURE_METHODS)
    end

    async_configurable :insecure_two_factor_methods_disallowed?

    # Clears restrictions on two-factor methods.
    #
    # returns: nothing
    def clear_disallowed_two_factor_methods(actor:, log_event: false)
      changed = config.delete(KEY, actor)

      return unless changed

      if log_event
        instrument :clear_disallowed_two_factor_methods, actor: actor
      end

      GitHub.dogstats.increment("two_factor.#{self.class.name.underscore}_settings.clear_all")
    end

    async_configurable :clear_disallowed_two_factor_methods

    # Removes restriction on provided two-factor method.
    #
    # returns: nothing
    def remove_disallowed_two_factor_method(method:, actor:, log_event: false)
      if METHODS_VALUES[method].nil?
        raise InvalidTwoFactorMethod, "Invalid two-factor method: #{method}"
      end

      disallowed = raw_two_factor_disallowed
      method_value = PrivateMethodOperators.value_from_method(method)

      # only need to do something if method actually is disallowed currently
      if PrivateMethodOperators.method_value_disallowed?(disallowed, method_value)
        new_disallowed = disallowed - method_value
        if new_disallowed == 0
          clear_disallowed_two_factor_methods(actor: actor, log_event: log_event)
        else
          config.set(KEY, new_disallowed, actor)
        end
      end

      if log_event
        instrument :remove_disallowed_two_factor_method, actor: actor
      end

      GitHub.dogstats.increment("two_factor.#{self.class.name.underscore}_settings.remove_method", tags: ["2fa_method:#{method}"])
    end

    async_configurable :remove_disallowed_two_factor_method

    # Adds restriction on provided two-factor method.
    #
    # returns: nothing
    def add_disallowed_two_factor_method(method:, actor:, force: false, log_event: false)
      if METHODS_VALUES[method].nil?
        raise InvalidTwoFactorMethod, "Invalid two-factor method: #{method}"
      end

      existing = raw_two_factor_disallowed
      method_value = PrivateMethodOperators.value_from_method(method)

      return if PrivateMethodOperators.method_value_disallowed?(existing, method_value)

      if existing.nil?
        config.set!(KEY, method_value, actor, force)
      else
        config.set!(KEY, existing | method_value, actor, force)
      end

      if log_event
        instrument :add_disallowed_two_factor_method, actor: actor
      end

      GitHub.dogstats.increment("two_factor.#{self.class.name.underscore}_settings.add_method", tags: ["2fa_method:#{method}"])
    end

    async_configurable :add_disallowed_two_factor_method

    # Allows insecure methods of 2FA
    #
    # returns: nothing
    def allow_insecure_two_factor_methods(actor:, log_event: false)
      remove_disallowed_two_factor_method(method: :insecure, actor: actor, log_event: log_event)
    end

    async_configurable :allow_insecure_two_factor_methods

    # Returns true if there is an inherited policy dictating disallowed methods
    def two_factor_disallowed_methods_policy?
      !!config.final?(KEY)
    end

    sig { params(businesses: T::Array[Business]).returns(T::Hash[Business, T::Set[Symbol]]) }
    private_class_method def self.filter_businesses_with_two_factor_disallowed_methods_unbatched(businesses)
      return Hash.new if businesses.empty?

      business_ids = businesses.map(&:id)

      # filter the businesses to only those that have any disallowed methods set
      # (bulk equivalent `get_two_factor_disallowed_methods!`)
      # QUERY 1
      business_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, business_ids: business_ids)).to_a
        SELECT target_id, value
        FROM configuration_entries
        WHERE (
          (target_type='Business' AND target_id IN (:business_ids))
        ) AND (
          name='two_factor.disallowed_methods'
        ) AND (
          value IS NOT NULL
        )
      SQL

      # build a lookup table for the businesses, so we can easily find them by ID
      biz_lookup = businesses.map { |t| [t.id, t] }.to_h
      # reconstruct the list of businesses that have the two factor requirement enabled
      businesses_with_disallowed_methods = Hash.new { |h, k| h[k] = [] }
      business_configuration_entries.each do |entry|
        biz = biz_lookup[entry["target_id"]]
        disallowed_methods = PrivateMethodOperators.methods_from_raw_value(entry["value"].to_i)
        businesses_with_disallowed_methods[biz] = disallowed_methods if biz
      end

      businesses_with_disallowed_methods
    end

    sig { params(organizations: T::Array[Organization]).returns(T::Hash[Organization, T::Set[Symbol]]) }
    private_class_method def self.filter_organizations_with_two_factor_disallowed_methods_unbatched(organizations)
      return Hash.new if organizations.empty?

      # build a lookup table for the orgs, so we can easily find them by ID
      org_lookup = organizations.map { |t| [t.id, t] }.to_h
      org_ids = organizations.map(&:id)

      # QUERY 1
      # run a query to find all of the orgs that have a business membership
      business_memberships = Business::OrganizationMembership
        .where(organization_id: org_ids)
        .pluck(:business_id, :organization_id)

      org_ids_with_business = []
      business_to_orgs_mapping = {}
      business_memberships.each do |business_id, org_id|
        business_to_orgs_mapping[business_id] ||= []
        business_to_orgs_mapping[business_id] << org_lookup[org_id]
        org_ids_with_business << org_id
      end
      business_ids = business_to_orgs_mapping.keys

      # filter the orgs to only those that have any disallowed methods set
      # we have to do this in two queries, one for orgs and one for businesses
      # (bulk equivalent `get_two_factor_disallowed_methods!`)
      # QUERY 2
      org_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, org_ids: org_ids)).to_a
        SELECT target_id, value
        FROM configuration_entries
        WHERE (
          (target_type='User' AND target_id IN (:org_ids))
        ) AND (
          name='two_factor.disallowed_methods'
        ) AND (
          value IS NOT NULL
        )
      SQL
      # QUERY 3
      business_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, business_ids: business_ids)).to_a
        SELECT target_id, value, final
        FROM configuration_entries
        WHERE (
          (target_type='Business' AND target_id IN (:business_ids))
        ) AND (
          name='two_factor.disallowed_methods'
        ) AND (
          value IS NOT NULL
        )
      SQL

      org_ids_with_disallowed_methods = org_configuration_entries.map { |entry| [entry["target_id"], entry["value"].to_i] }
      business_ids_with_disallowed_methods = business_configuration_entries.map { |entry| [entry["target_id"], entry["value"].to_i, entry["final"] == 1] }

      # reconstruct the list of orgs that have disallowed methods
      # either through the org itself, or through the business that owns the org
      orgs_with_disallowed_methods = Hash.new { |h, k| h[k] = [] }

      org_ids_with_disallowed_methods.each do |org_id, value|
        org = org_lookup[org_id]
        orgs_with_disallowed_methods[org] = PrivateMethodOperators.methods_from_raw_value(value) if org
      end
      business_ids_with_disallowed_methods.each do |business_id, value, final|
        orgs = business_to_orgs_mapping[business_id]
        disallowed_methods = PrivateMethodOperators.methods_from_raw_value(value.to_i)
        if orgs && orgs.any?
          if final
            # if business config is final, override any existing org config (by replacing value in hash)
            orgs.each do |org|
              orgs_with_disallowed_methods[org] = disallowed_methods
            end
          else
            # else, business value is only respected if an org doesn't have anything set
            orgs.each do |org|
              orgs_with_disallowed_methods[org] = disallowed_methods unless orgs_with_disallowed_methods[org].present?
            end
          end
        end
      end

      orgs_with_disallowed_methods
    end

    private

    def raw_two_factor_disallowed
      config.get(KEY)&.to_i
    end

    def invalid_two_factor_methods_available?
      T.bind(self, T.any(Organization, Business))
      self.can_disallow_two_factor_methods?
    end

    # Logic that does some of the bitwise logic that this configurable uses
    # Please keep usages within only the TwoFactorDisallowedMethods module
    module PrivateMethodOperators
      def self.methods_from_raw_value(raw_value)
        methods = Set.new
        METHODS_VALUES.each do |name, value|
          if method_value_disallowed?(raw_value, value)
            if name == :insecure
              methods = methods | INSECURE_METHODS
            else
              methods << :"#{name}"
            end
          end
        end

        methods
      end

      def self.value_from_method(method)
        METHODS_VALUES[:"#{method}"]
      end

      def self.method_value_disallowed?(setting, method_value)
        return false if setting.nil?

        setting & method_value == method_value
      end
    end
  end
end
