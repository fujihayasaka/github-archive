# typed: strict
# frozen_string_literal: true

module Codespaces
  class GetRegionForUser < Command

    include GitHub::Memoizer

    sig { returns(::User) }
    attr_reader :user

    sig { returns(T.nilable(::Repository)) }
    attr_reader :repository

    sig { returns(T.nilable(String)) }
    attr_reader :requested_location

    sig { returns(T.nilable(String)) }
    attr_reader :client_ip

    sig { returns(Symbol) }
    attr_reader :client

    sig do
      params(
        user: ::User,
        repository: T.nilable(::Repository),
        requested_region: T.nilable(T.any(String, Codespaces::Locations::Region)),
        requested_geo: T.nilable(T.any(String, Codespaces::Locations::Geo)),
        requested_location: T.nilable(String), # Legacy support for API. Can be either a Region or a Geo
        client_ip: T.nilable(String),
        client: T.nilable(Symbol),
        vscs_target: T.any(String, Symbol)
      ).void
    end
    def initialize(user:, repository:, requested_region: nil, requested_geo: nil, requested_location: nil, client_ip: nil, client: nil, vscs_target: Codespaces::Vscs.default_target)
      @user = user
      @repository = repository
      @requested_region = requested_region
      @requested_geo = requested_geo
      @requested_location = requested_location
      @client_ip = client_ip
      @client = T.let(client || :unknown, Symbol)
      @vscs_target = T.let(vscs_target.to_sym, Symbol)
    end

    sig { override.returns(String) }
    def perform
      if network_configuration.present?
        optimal_network_configuration_region
      elsif region_from_requested_location || requested_region
        requested_region_with_backup
      else
        optimal_region_from_geolocation
      end
    end

    private

    sig { returns(String) }
    def optimal_network_configuration_region
      permitted_stamps = possible_stamps.where(region: T.must(network_configuration).regions)
      requested_stamp = requested_geo && permitted_stamps.where(geo: requested_geo).first

      stamp = requested_stamp ||
        permitted_stamps.closest_available(user:, client_ip: client_ip) ||
        Codespaces::VscsServiceStamp.where(vscs_target:, region: T.must(network_configuration).regions).closest_available(user:, client_ip: client_ip)

      raise Codespaces::Locations::Region::UnavailableError, "No regions are currently available to the user" unless stamp

      stamp.region.id
    end

    sig { returns(String) }
    def requested_region_with_backup
      # If we have a singular requested region we have to try to use it.
      stamp = possible_stamps.where(region: region_from_requested_location || requested_region).first
      raise Codespaces::Locations::Region::InvalidError, "Location is invalid" unless stamp
      if user.feature_flag_enabled_or_raise?(:codespaces_developer) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return stamp.region.id if stamp.available_for_creates?(user: user)

        backup = stamp.backup(user:, region_locator:)
        if backup
          backup.region.id
        else
          raise Codespaces::Locations::Region::UnavailableError.new("Region '#{stamp.region.id}' is unavailable and currently has no available backups.")
        end
      else
        # We received a requested region from a non-staff user. Treat this as if they requested the associated geo instead.
        optimal_region_from_geolocation(geo: stamp.geo)
      end
    end

    sig { params(geo: T.nilable(Codespaces::Locations::Geo)).returns(String) }
    def optimal_region_from_geolocation(geo: requested_geo || geo_from_requested_location || geo_from_settings)
      if stamp = possible_stamps.where(geo:).closest_available(user:, client_ip: client_ip)
        stamp.region.id
      else
        raise Codespaces::Locations::Region::UnavailableError, "No regions are currently available to the user"
      end
    end

    # A generic `location` parameter is used in some places such as the API that historically allowed regions
    # but we want it to actually specify geos moving forward. This allows for either but if a region is specified
    # we treat it basically as an alias for its geo.
    sig { returns(T.nilable(Codespaces::Locations::Geo)) }
    def geo_from_requested_location
      return unless requested_location.present?

      Codespaces::Locations::Geo.find(requested_location) || Codespaces::Locations::Region.find(requested_location)&.geo || raise(Codespaces::Locations::Region::InvalidError, "Location is invalid")
    end

    sig { returns(T.nilable(Codespaces::Locations::Region)) }
    def region_from_requested_location
      return unless requested_location.present?

      Codespaces::Locations::Region.find(requested_location)
    end

    sig { params(kwargs: T.anything).returns(Codespaces::VscsServiceStamp::Collection) }
    def possible_stamps(**kwargs)
      if prebuilds_configured
        Codespaces::VscsServiceStamp.available_for_prebuilds(repository:, vscs_target:, **kwargs)
      else
        Codespaces::VscsServiceStamp.where(vscs_target:, **kwargs)
      end
    end

    sig { returns(Codespaces::Locations::RegionLocator) }
    memoize def region_locator
      Codespaces::Locations::RegionLocator.new(user, client_ip: client_ip, vscs_target: vscs_target)
    end

    sig { returns(T::Boolean) }
    memoize def prebuilds_configured
      repository.present? ? Codespaces::Prebuilds.configured?(repository) : false
    end

    sig { returns(T.nilable(Codespaces::Locations::Geo)) }
    memoize def geo_from_settings
      geo = Codespaces::Locations::Region.find(Codespaces::Settings.for_user(user).default_location)&.geo
      # Ignore the geo specified in the user's settings if it results in no available stamps with the provided target.
      # This would only happen with a non-production target and would implicitly result in only the stamps for that
      # target being used in optimal_region_from_geolocation above (same as if the user had no saved preference).
      Codespaces::VscsServiceStamp.where(geo:, vscs_target:).none? ? nil : geo
    end

    sig { returns(Symbol) }
    memoize def vscs_target
      # Ignore invalid vscs_targets in favor of the default
      Codespaces::Vscs::TargetConfig.for(@vscs_target)&.name || Codespaces::Vscs.default_target
    end

    sig { returns(T.nilable(Codespaces::Locations::Region)) }
    memoize def requested_region
      return unless @requested_region.present?
      return @requested_region if @requested_region.is_a?(Codespaces::Locations::Region)

      Codespaces::Locations::Region.find(@requested_region) || raise(Codespaces::Locations::Region::InvalidError, "Location is invalid")
    end

    sig { returns(T.nilable(Codespaces::Locations::Geo)) }
    memoize def requested_geo
      return unless @requested_geo.present?
      return @requested_geo if @requested_geo.is_a?(Codespaces::Locations::Geo)

      Codespaces::Locations::Geo.find(@requested_geo) || raise(Codespaces::Locations::Geo::InvalidError, "The geo '#{@requested_geo}' is not recognized.")
    end

    sig { returns(T.nilable(User)) }
    memoize def billable_owner
      return unless repository.present? && user.present?

      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(user, repository).sync
      repository_policy.billable_owner
    end

    sig { returns(T.nilable(Codespaces::NetworkConfiguration)) }
    memoize def network_configuration
      return unless billable_owner.present? && repository.present? && user.present?

      Codespaces::NetworkConfiguration.for(repository: T::must(repository), billable_owner: T::must(billable_owner), actor: user)
    end
  end
end
