# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class VscsServiceStamp
    # A ServiceStamp (not a Proxima stamp) is the intersection of a vscs_target/environment and single region.
    include ActiveModel::API
    include Comparable
    include GitHub::Memoizer

    ALL = {
      production: [
        {
          region: "AustraliaCentral",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "AustraliaEast",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "EastUs",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "EastUs2",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "CentralIndia",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "SouthEastAsia",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "UkSouth",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "WestEurope",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "WestUs2",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "WestUs3",
          availability: :ga,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
      ],
      ppe: [
        {
          region: "SouthEastAsia",
          availability: :internal,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
        {
          region: "CanadaCentral",
          availability: :internal,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
      ],
      development: [
        {
          region: "WestUs2",
          availability: :internal,
          prebuild_templates_allowed: true,
          prebuilds_available: true,
        },
      ]
    }

    ALL[:local] = ALL[:development]
    ALL[:latestdev] = ALL[:development]
    ALL[:latestppe] = ALL[:ppe]
    ALL[:latestprod] = ALL[:production].deep_dup.map { |stamp| stamp[:availability] = :internal; stamp }
    ALL.freeze

    attr_writer   :region
    attr_accessor :vscs_target, :availability, :prebuild_templates_allowed, :prebuilds_available

    private_class_method :new

    def self.all
      @all ||= ALL.flat_map do |vscs_target, stamps|
        stamps.map do |stamp|
          new(
            region: stamp[:region],
            vscs_target: vscs_target,
            availability: stamp[:availability],
            prebuild_templates_allowed: stamp[:prebuild_templates_allowed],
            prebuilds_available: stamp[:prebuilds_available],
          )
        end
      end
    end
    private_class_method :all

    def self.public
      # Require the stamp to have a region. The only way a stamp will be missing a region is if it has been restricted
      # by Proxima.
      Collection.new(all.select { |stamp| stamp.region })
    end

    def self.where(...)
      public.where(...)
    end

    def self.find(...)
      public.find(...)
    end

    def self.closest_available(user:, vscs_target:, client_ip: nil, **args)
      where(available_for_creates_to: user, vscs_target: vscs_target, **args).closest_available(client_ip: client_ip)
    end

    def self.available_for_prebuilds(repository: nil, **args)
      # Certain repositories can be flagged in to allow usage of prebuilds earlier than we otherwise
      # allow via stamp configuration.
      if repository && GitHub.flipper[:codespaces_prebuilds_new_regions].enabled?(repository)
        where(**args)
      else
        where(**args, prebuilds_available: true)
      end
    end

    delegate :geo, to: :region
    delegate :available?, :available_to?, :available_for_creates?, :available_for_resumes?, to: :availability_service
    delegate :percent_available_for_creates, :percent_available_for_resumes, :failover, :failback, to: :availability_service

    memoize def id
      (region.id.to_s + "-" + vscs_target.to_s).downcase
    end

    alias_method :to_s, :id

    def region
      Codespaces::Locations::Region.find(@region)
    end

    memoize def target_config
      Codespaces::Vscs::TargetConfig.for(@vscs_target)
    end

    def ga?
      availability == :ga
    end

    def internal?
      availability == :internal
    end

    def available_backups(user:)
      available_backups = self.class.where(geo: region.geo, vscs_target: target_config.name, available_to: user).without(self)
      if user.feature_enabled?(:codespaces_geoconstrained_backups)
        # Base case is that we have at least one other available service deployment in the same target+geo as this one
        if available_backups.any? || target_config.production?
          available_backups
        else
          # This should only happen for non-production service deployments. In that
          # case we will look at all service deployments in the same environment (while still respecting Proxima) and return
          # one the user can access.
          self.class.where(vscs_target: target_config.name, available_to: user).without(self)
        end
      else
        # Base case is that we have at least one other available service deployment in the same target+geo as this one
        return available_backups if available_backups.any?

        # This should only happen for non-production service deployments OR if literally an entire geo is down. In that
        # case we will look at all service deployments in the same environment (while still respecting Proxima) and return
        # one the user can access.
        self.class.where(vscs_target: target_config.name, available_to: user).without(self)
      end
    end

    def backup(user:, region_locator: nil, client_ip: nil)
      available_backups = available_backups(user:)
      # No reason to muck around with region locator if we only have one backup option
      return available_backups.first if available_backups.one?

      region_locator ||= Codespaces::Locations::RegionLocator.new(user, client_ip: client_ip, vscs_target: vscs_target)
      if region = region_locator.from_ip_location_lookup(locations: available_backups.map { |stamp| stamp.region.id })
        # Turn this back into a VscsServiceStamp object
        self.class.find(region:, vscs_target: vscs_target)
      elsif region = region_locator.from_coordinates(self.region.latitude, self.region.longitude, locations: available_backups.map { |stamp| stamp.region.id })
        # Turn this back into a VscsServiceStamp object
        self.class.find(region:, vscs_target: vscs_target)
      else
        available_backups.sample
      end
    end

    def api_url
      GitHub.cache.fetch("codespaces_#{id}_api_url", ttl: 6.hours) do
        begin
          response = Codespaces::AnonymousVscsClient.new(api_url: target_config.api_url).get("api/v1/locations")
          if response.success?
            api_url = JSON.parse(response.body)["hostnames"][region.id]
            api_url.present? ? "https://#{api_url}" : target_config.api_url
          else
            target_config.api_url
          end
        rescue StandardError
          target_config.api_url
        end
      end
    end

    def eql?(other)
      super || (
        self.class == other.class &&
        !id.nil? &&
        id == other.id
      )
    end
    alias_method :==, :eql?

    def <=>(other)
      return nil unless other.class == self.class

      id <=> other.id
    end

    private

    def availability_service
      Codespaces::VscsServiceStampAvailability.new(self)
    end

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

        ids = ids.map do |id|
          if id.kind_of?(Hash)
            (id[:region].to_s + "-" + id[:vscs_target].to_s).downcase
          else
            id
          end
        end
        ids.one? ? where(id: ids.first).first : where(id: ids).to_a
      end

      def closest_available(user: nil, vscs_target: nil, client_ip: nil)
        # The user and vscs_target must either be provided as args here or have already been provided to the `where` chain
        # to determine the closest available stamp.
        where(available_for_creates_to: user) if user
        where(vscs_target:) if vscs_target
        raise ArgumentError, "Must provide both a user and a vscs_target" unless @where[:available_for_creates_to] && @where[:vscs_target]

        possible_stamps = to_a
        return possible_stamps.first if possible_stamps.one?

        # If we have multiple stamps available, try to select the best one based on the user's location
        locator = Codespaces::Locations::RegionLocator.new(@where[:available_for_creates_to], client_ip: client_ip)
        if region = locator.from_ip_location_lookup(locations: possible_stamps.map { |stamp| stamp.region.id })
          # Turn this back into a VscsServiceStamp object
          VscsServiceStamp.find(region:, vscs_target: @where[:vscs_target])
        else
          possible_stamps.sample
        end
      end

      memoize def to_a
        return [] if @where.values.any? { |v| v == [] }

        results = @data

        if geo = @where[:geo]
          geos = Codespaces::Locations::Geo.where(id: geo)
          results = results.select { |stamp| geos.include?(stamp.geo) }
        end
        if region = @where[:region]
          regions = Codespaces::Locations::Region.where(id: region)
          results = results.select { |stamp| regions.include?(stamp.region) }
        end
        if vscs_target = @where[:vscs_target].presence
          results = results.select { |stamp| stamp.target_config.to_s == vscs_target.to_s }
        end
        if available_to = @where[:available_to]
          results = results.select { |stamp| stamp.available?(user: available_to) }
        end
        if available_for_creates_to = @where[:available_for_creates_to]
          results = results.select { |stamp| stamp.available_for_creates?(user: available_for_creates_to) }
        end
        if @where[:prebuilds_available]
          results = results.select { |stamp| stamp.prebuilds_available }
        end
        if @where[:prebuild_templates_allowed] == true
          results = results.select { |stamp| stamp.prebuild_templates_allowed }
        end
        if id = @where[:id]
          case id
          when Array
            ids = id.map(&:downcase)
            results = results.select { |stamp| ids.include?(stamp.id.downcase) }
          when Codespaces::VscsServiceStamp
            results = results.select { |stamp| stamp == id }
          else
            results = results.select { |stamp| stamp.id.downcase == id.downcase }
          end
        end

        results
      end

      delegate_missing_to :to_a
      delegate :each, to: :to_a
    end
  end
end
