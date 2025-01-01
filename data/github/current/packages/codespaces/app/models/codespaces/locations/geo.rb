# typed: true
# frozen_string_literal: true

# This class represents a group of geographically-associated Azure regions (see corresponding
# ::Region class) for use with codespaces. Our goal is to surface these abstract groups to end
# users rather than specific individual region names. This allows failover between regions and
# avoids a region-specific contract with the user.
module Codespaces::Locations
  class Geo
    InvalidError = Class.new(StandardError)

    include ActiveModel::API
    include Comparable

    ALL = [
      {
          id: "UsEast",
          name: "US East",
          group_name: "United States",
          legacy_region: "EastUs",
      },
      {
          id: "UsWest",
          name: "US West",
          group_name: "United States",
          legacy_region: "WestUs2",
      },
      {
          id: "EuropeWest",
          name: "Europe West",
          group_name: "Europe",
          legacy_region: "WestEurope",
      },
      {
          id: "SoutheastAsia",
          name: "Southeast Asia",
          group_name: "Asia Pacific",
          legacy_region: "SouthEastAsia",
      },
      {
        id: "Australia",
        name: "Australia",
        group_name: "Asia Pacific",
      }
    ].freeze

    attr_accessor :id, :name, :group_name
    # These are used to support rolling out new geos. Both are required if attempting to use geo rollouts.
    attr_accessor :rollout_feature_flag, :previous_geo_id
    attr_accessor :legacy_region # TODO we should stop using this completely...

    private_class_method :new

    def self.all
      @all ||= ALL.map { |geo| new(geo) }
    end
    private_class_method :all

    def self.unsafe_find(*args)
      # Don't use this... it's only here to be used by the Region model to avoid an infinite loop
      Collection.new(all).find(args)
    end

    # Returns all regions that are visible given the current stamp's Proxima configuration.
    def self.public
      Collection.new(all.select { |geo| geo.regions.any? })
    end

    def self.where(...)
      public.where(...)
    end

    def self.find(...)
      public.find(...)
    end

    # A geo can either exist or not in the context of a vscs_target based on whether
    # there are any stamps in this geo's regions.
    def exists?(vscs_target: Codespaces::Vscs.default_target)
      Codespaces::VscsServiceStamp.where(geo: self, vscs_target:).any?
    end

    # A geo is available to a user if any of its regions are currently available.
    def available?(user:)
      available_regions(user:).any?
    end

    def regions
      Codespaces::Locations::Region.where(geo: self)
    end

    def primary_region
      # This shouldn't even exist but we need it for a bit longer. This maps a geo to either a legacy region if it has
      # one or the first region in the list if it doesn't (to support the upcoming Australia geo which won't have this
      # baggage)
      legacy_region ? regions.find(legacy_region) : regions.sort.first
    end
    delegate :id, to: :primary_region, prefix: true, allow_nil: true

    def available_regions(user:)
      Codespaces::Locations::Region.where(geo: self, available_to: user)
    end

    def stamps
      Codespaces::VscsServiceStamp.where(geo: self)
    end

    def available_stamps(user:)
      Codespaces::VscsServiceStamp.where(geo: self, available_to: user)
    end

    def <=>(other)
      return nil unless other.class == self.class

      id <=> other.id
    end

    alias_method :to_s, :id

    class Collection
      include Enumerable
      include GitHub::Memoizer

      def initialize(data)
        @data = data
        @where = {}
      end

      def where(**kwargs)
        @where.merge!(kwargs)
        self
      end

      def find(*ids)
        ids = ids.compact
        return unless ids.present?

        ids.one? ? where(id: ids.first).first : where(id: ids).to_a
      end

      memoize def to_a
        return [] if @where.values.any? { |v| v == [] }

        results = @data
        if vscs_target = @where[:vscs_target]&.presence
          results = results.select { |geo| geo.exists?(vscs_target: vscs_target) }
        end
        if available_to = @where[:available_to]
          results = results.select { |geo| geo.available?(user: available_to) }
        end
        if primary_region = @where[:primary_region]&.presence
          case primary_region
          when Codespaces::Locations::Region
            results = results.select { |geo| geo.primary_region == primary_region }
          else
            region = Codespaces::Locations::Region.find(primary_region)
            return [] if region.nil?
            results = results.select { |geo| geo.primary_region == region }
          end
        end
        if id = @where[:id]&.presence
          case id
          when Array
            ids = id.map(&:downcase)
            results = results.select { |geo| ids.include?(geo.id.downcase) }
          when Codespaces::Locations::Geo
            results = results.select { |geo| geo == id }
          else
            results = results.select { |geo| geo.id.downcase == id.downcase }
          end
        end
        results
      end

      delegate_missing_to :to_a
      delegate :each, to: :to_a
    end
  end
end
