# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Codespaces::Locations
  class Region
    UnavailableError = Class.new(StandardError)
    InvalidError = Class.new(StandardError)

    include ActiveModel::API
    include Comparable
    include GitHub::Memoizer

    ALL = [
      {
        id: "AustraliaCentral",
        name: "Australia Central",
        coordinates: [-35.3075, 149.1244], # Canberra, Australian Capital Territory
        logical_geo: "Australia",
        physical_geo: "au",
      },
      {
        id: "AustraliaEast",
        name: "Australia East",
        coordinates: [-33.867778, 151.21], # Sydney, New South Wales
        logical_geo: "Australia",
        physical_geo: "au",
      },
      {
        id: "EastUs",
        name: "US East",
        coordinates: [38.751389, -77.476389],
        logical_geo: "UsEast",
        physical_geo: "us",
      },
      {
        id: "EastUs2",
        name: "US East 2",
        coordinates: [36.668056, -78.388889], # Boydton, Virginia
        logical_geo: "UsEast",
        physical_geo: "us",
      },
      {
        id: "CentralIndia",
        name: "Central India",
        coordinates: [18.5204, 73.8567], # Pune, India
        logical_geo: "SoutheastAsia",
        physical_geo: "apac",
      },
      {
        id: "SouthEastAsia",
        name: "Southeast Asia",
        coordinates: [1.283333, 103.833333],
        logical_geo: "SoutheastAsia",
        physical_geo: "apac",
      },
      {
        id: "UkSouth",
        name: "UK South",
        coordinates: [50.96983, -0.88263], # South Harting, England
        logical_geo: "EuropeWest",
        physical_geo: "uk",
      },
      {
        id: "WestEurope",
        name: "Europe West",
        coordinates: [52.377956, 4.897070],
        logical_geo: "EuropeWest",
        physical_geo: "eu",
      },
      {
        id: "WestUs2",
        name: "US West",
        coordinates: [47.2342997, -119.8525504],
        logical_geo: "UsWest",
        physical_geo: "us",
      },
      {
        id: "WestUs3",
        name: "US West 3",
        coordinates: [33.608889, -112.324722], # El Mirage, Arizona
        logical_geo: "UsWest",
        physical_geo: "us",
      },
      {
        id: "CanadaCentral",
        name: "Canada Central",
        coordinates: [43.6532, -79.3832], # Toronto, Ontario
        # Reasoning for why we chose the geo which has a geographical mis-match: https://github.com/github/codespaces/issues/18916#issuecomment-2311112276
        logical_geo: "UsEast",
        physical_geo: "ca",
      },
    ].freeze

    attr_accessor :id, :name, :coordinates, :physical_geo, :legacy_user_selectable
    attr_writer :logical_geo

    private_class_method :new

    def self.all
      @all ||= ALL.map { |region| new(region) }
    end
    private_class_method :all

    # Returns all regions that are visible given the current stamp's Proxima configuration.
    def self.public
      regions = Collection.new(all)

      azure_geo = GitHub.codespaces_stamp_azure_geo
      raise "No azure geo configured for stamp" if GitHub.multi_tenant_enterprise? && !azure_geo.present?
      return regions if azure_geo.blank? || azure_geo == "all"

      regions.where(physical_geo: azure_geo.to_s)
    end

    def self.where(...)
      public.where(...)
    end

    def self.find(...)
      public.find(...)
    end

    def logical_geo
      original_geo = Geo.unsafe_find(@logical_geo)
      return @logical_geo unless original_geo.rollout_feature_flag.present?
      return @logical_geo if GitHub.flipper[original_geo.rollout_feature_flag].enabled?

      original_geo.previous_geo_id or raise "No disabled geo configured for #{original_geo.id}"
    end

    def geo
      Geo.find(logical_geo)
    end

    def latitude
      coordinates[0]
    end

    def longitude
      coordinates[1]
    end

    def stamp(vscs_target:)
      Codespaces::VscsServiceStamp.find(region: self, vscs_target:)
    end

    def stamps
      Codespaces::VscsServiceStamp.where(region: self)
    end

    def available_stamps(user:)
      Codespaces::VscsServiceStamp.where(region: self, available_to: user)
    end

    # A region is available to a user if it has any available stamps that the user has access to
    def available?(user:)
      available_stamps(user:).any?
    end

    def exists?(vscs_target: Codespaces::Vscs.default_target)
      Codespaces::VscsServiceStamp.find(region: self, vscs_target:).present?
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
        if physical_geo = @where[:physical_geo]
          results = results.select { |region| region.physical_geo.downcase == physical_geo.to_s.downcase }
        end
        if geo = @where[:geo]&.presence
          # Due to the circular relationship between Region and Geo we can't use Codespaces::Locations::Geo.where(id: geo) here
          # since that triggers a check on if the Geo has any visible regions to filter things out for Proxima.
          case geo
          when Array
            geos = geo.map(&:downcase)
            results = results.select { |region| geos.include?(region.logical_geo.downcase) }
          when Codespaces::Locations::Geo
            results = results.select { |region| region.logical_geo == geo.id }
          else
            results = results.select { |region| region.logical_geo.downcase == geo.to_s.downcase }
          end
        end
        if vscs_target = @where[:vscs_target]&.presence
          results = results.select { |region| region.exists?(vscs_target: vscs_target) }
        end
        if available_to = @where[:available_to]
          results = results.select { |region| region.available?(user: available_to) }
        end
        if id = @where[:id]&.presence
          case id
          when Array
            ids = id.map(&:downcase)
            results = results.select { |region| ids.include?(region.id.downcase) }
          when Codespaces::Locations::Region
            results = results.select { |region| region == id }
          else
            results = results.select { |region| region.id.downcase == id.downcase }
          end
        end
        results
      end

      delegate_missing_to :to_a
      delegate :each, to: :to_a
    end
  end
end
