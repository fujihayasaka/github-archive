# typed: true
# frozen_string_literal: true

module Configurable
  module TwoFactorRequired
    include Instrumentation::Model
    extend Configurable::Async
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "two_factor.required".freeze
    FILTER_BATCH_SIZE = 10000

    # Public: Is the two factor requirement enabled for the configurable?
    #
    # Returns a Boolean.
    def two_factor_requirement_enabled?
      GitHub.tracer.in_span("Configurable::TwoFactorRequired#two_factor_requirement_enabled?") do |_span|
        config.enabled?(KEY)
      end
    end

    # used for CAP filtering to reduce the queries we make to the configuration_entries table
    # performs the :two_factor_cap_enforcement feature flag checks as well
    # note - considered using the `Configurable.preload_configuration` method instead of implementing this, but that method is a bit more generalized and would have resulted in more queries
    def self.filter_businesses_with_two_factor_requirement_enabled(businesses)
      return [] if businesses.empty?
      businesses.each_slice(FILTER_BATCH_SIZE).with_object([]) do |slice, memo|
        memo.concat(filter_businesses_with_two_factor_requirement_enabled_unbatched(slice))
      end.uniq
    end

    # used for CAP filtering to reduce the queries we make to the configuration_entries table
    # performs the :two_factor_cap_enforcement feature flag checks as well
    # note - considered using the `Configurable.preload_configuration` method instead of implementing this, but that method is a bit more generalized and would have resulted in more queries
    def self.filter_organizations_with_two_factor_requirement_enabled(organizations)
      return [] if organizations.empty?
      organizations.each_slice(FILTER_BATCH_SIZE).with_object([]) do |slice, memo|
        memo.concat(filter_organizations_with_two_factor_requirement_enabled_unbatched(slice))
      end.uniq
    end

    async_configurable :two_factor_requirement_enabled?

    # Public: Is the two factor requirement disabled for the configurable?
    #
    # Returns a Boolean.
    def two_factor_requirement_disabled?
      !two_factor_requirement_enabled?
    end

    # Disables two-factor authentication being required. If force is true this will create a config entry
    # that sets a policy enforcing the setting for children. If not forced, any config entry will
    # be deleted.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def disable_two_factor_required(actor:, force: false, log_event: false)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      return unless changed

      if log_event
        instrument :disable_two_factor_requirement, actor: actor
      end
      GitHub.dogstats.increment("two_factor_required.#{self.class.name.underscore}_settings.disable")
    end

    # Enables two-factor authentication requirement. If force is true a policy will be created
    # that applies to children.
    #
    # force: forces the setting to override any child objects
    # actor: the user making the change
    # log_event: Boolean indicating whether to instrument this event. Defaults to false.
    #
    # returns: nothing
    def enable_two_factor_required(actor:, force: false, log_event: false)
      changed = config.enable!(KEY, actor, force)

      return unless changed

      if log_event
        instrument :enable_two_factor_requirement, actor: actor
      end
      GitHub.dogstats.increment("two_factor_required.#{self.class.name.underscore}_settings.enable")
    end

    # is there a policy enabling/disabling two-factor authentication?
    def two_factor_required_policy?
      !!config.final?(KEY)
    end

    private_class_method def self.filter_businesses_with_two_factor_requirement_enabled_unbatched(businesses)
      return [] if businesses.empty?

      # filter the businesses to only those that have the feature flag enabled
      feature_enabled_businesses = businesses.filter { |b| b.two_factor_cap_enforcement_enabled? }
      feature_enabled_business_ids = feature_enabled_businesses.map(&:id)
      return [] if feature_enabled_business_ids.empty?

      # filter the businesses further, to only those that have the two factor requirement enabled
      # (bulk equivalent `two_factor_requirement_enabled?``)
      # QUERY 1
      business_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, business_ids: feature_enabled_business_ids)).to_a
        SELECT name, value, final, target_id
        FROM configuration_entries
        WHERE (
          (target_type='Business' AND target_id IN (:business_ids))
        ) AND (
          name='two_factor.required'
        ) AND (
          value='true'
        )
      SQL

      # build a lookup table for the businesses, so we can easily find them by ID
      biz_lookup = businesses.map { |t| [t.id, t] }.to_h
      # reconstruct the list of businesses that have the two factor requirement enabled
      businesses_with_two_factor_requirement = []
      business_configuration_entries.each do |entry|
        biz = biz_lookup[entry["target_id"]]
        businesses_with_two_factor_requirement << biz if biz
      end

      businesses_with_two_factor_requirement.uniq
    end

    private_class_method def self.filter_organizations_with_two_factor_requirement_enabled_unbatched(organizations)
      return [] if organizations.empty?

      # filter the orgs to only those that have the feature flag enabled
      # this checks the org, and .business
      # QUERY -- note that this queries the business on each org for the feature flag check. This will be removed after we get this thing rolled out
      feature_enabled_organizations = organizations.filter { |o| o.feature_enabled?(:two_factor_cap_enforcement) }
      return [] if feature_enabled_organizations.empty?

      # build a lookup table for the orgs, so we can easily find them by ID
      org_lookup = feature_enabled_organizations.map { |t| [t.id, t] }.to_h

      # QUERY 1
      # run a query to find all of the orgs that have a business membership
      feature_enabled_organization_ids = feature_enabled_organizations.map(&:id)
      business_memberships = Business::OrganizationMembership
        .where(organization_id: feature_enabled_organization_ids)
        .pluck(:business_id, :organization_id)

      organization_ids_with_business = []
      business_to_orgs_mapping = {}
      business_memberships.each do |business_id, organization_id|
        business_to_orgs_mapping[business_id] ||= []
        business_to_orgs_mapping[business_id] << org_lookup[organization_id]
        organization_ids_with_business << organization_id
      end
      feature_enabled_business_ids = business_to_orgs_mapping.keys

      # filter the orgs further, to only those that have the two factor requirement enabled
      # we have to do this in two queries, one for orgs and one for businesses
      # (bulk equivalent `two_factor_requirement_enabled?`)
      # QUERY 2
      org_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, org_ids: feature_enabled_organization_ids)).to_a
        SELECT target_id
        FROM configuration_entries
        WHERE (
          (target_type='User' AND target_id IN (:org_ids))
        ) AND (
          name='two_factor.required'
        ) AND (
          value='true'
        )
      SQL
      # QUERY 3
      business_configuration_entries = ApplicationRecord::Domain::ConfigurationEntries.connection.select_all(Arel.sql(<<-SQL, business_ids: feature_enabled_business_ids)).to_a
        SELECT target_id
        FROM configuration_entries
        WHERE (
          (target_type='Business' AND target_id IN (:business_ids))
        ) AND (
          name='two_factor.required'
        ) AND (
          value='true'
        )
      SQL

      # reconstruct the list of orgs that have the two factor requirement enabled
      # either through the org itself, or through the business that owns the org
      org_ids_with_two_factor_requirement = org_configuration_entries.map { |entry| entry["target_id"] }
      business_ids_with_two_factor_requirement = business_configuration_entries.map { |entry| entry["target_id"] }
      orgs_with_two_factor_requirement = []
      org_ids_with_two_factor_requirement.each do |org_id|
        org = org_lookup[org_id]
        orgs_with_two_factor_requirement << org if org
      end
      business_ids_with_two_factor_requirement.each do |business_id|
        orgs = business_to_orgs_mapping[business_id]
        orgs_with_two_factor_requirement.concat(orgs) if orgs && orgs.any?
      end

      orgs_with_two_factor_requirement.uniq
    end
  end
end
