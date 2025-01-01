# typed: true
# frozen_string_literal: true

module Codespaces::Locations
  class RegionLocator
    class Point
      attr_reader :latitude, :longitude

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
      end
    end
    include GitHub::ResilienceMixin

    attr_reader :vscs_target

    def initialize(user, client_ip: nil, vscs_target: nil)
      @user = user
      @client_ip = client_ip
      @vscs_target = vscs_target
    end

    def from_ip_location_lookup(locations: Codespaces::Locations::Region.where(vscs_target: vscs_target).map(&:id))
      location = last_known_good_location

      from_coordinates(location[:latitude], location[:longitude], locations:) if location
    end

    def from_coordinates(latitude, longitude, locations: Codespaces::Locations::Region.where(vscs_target: vscs_target).map(&:id))
      if latitude && longitude
        point = Point.new(latitude, longitude)
        closest_azure_region(point, locations)
      end
    end

    private

    def last_known_good_location
      # First check if we were explicitly provided a client IP
      if @client_ip
        location = GitHub::Location.look_up(@client_ip)
        if location.present? && location[:latitude] && location [:longitude]
          GitHub.dogstats.increment("codespaces.location_ip_lookup", tags: ["ip_source:client_ip_param"])
          return location
        end
      end

      # Second, we'll try to get the location from the current request's actor IP
      if actor_ip = GitHub.context.to_hash[:actor_ip]
        location = GitHub::Location.look_up(actor_ip)
        if location.present? && location[:latitude] && location[:longitude]
          GitHub.dogstats.increment("codespaces.location_ip_lookup", tags: ["ip_source:context_actor_ip"])
          return location
        end
      end

      # Lastly, we'll start with the most recent auth record and move backwards
      # until we find a valid location based on the IP at time of authentication
      # Limit to last 100 auth records, 98.4% of users have fewer than that today per Datadot.
      auth_record = with_database_error_fallback(fallback: nil) do
        @user.authentication_records.order(created_at: :desc, id: :desc).limit(100).find do |ar|
          location = ar.location
          location[:latitude] && location[:longitude]
        end
      end

      location = auth_record&.location
      if location.present? && location[:latitude] && location[:longitude]
        GitHub.dogstats.increment("codespaces.location_ip_lookup", tags: ["ip_source:auth_record"])
        return location
      end

      nil # no valid location found
    end

    def closest_azure_region(user_point, locations)
      distances = locations.map do |location|
        coords = Codespaces::Locations::Region.find(location).coordinates
        [location, self.distance_between(user_point, Point.new(*coords))]
      end

      sorted_distances = distances.min do |a, b|
        a.second <=> b.second
      end

      sorted_distances&.first
    end

    # This implements the haversine formula for finding the distance between
    # two points on a sphere (Earth, in this case)
    # https://en.wikipedia.org/wiki/Haversine_formula
    def distance_between(point1, point2)
      r = 6378.137 # Radius of the earth at the equator in km
      lat_rad_1 = point1.latitude * Math::PI / 180
      lat_rad_2 = point2.latitude * Math::PI / 180
      delta_lat_rad = (point2.latitude - point1.latitude) * Math::PI / 180
      delta_long_rad = (point2.longitude - point1.longitude) * Math::PI / 180

      a = ((Math.sin(delta_lat_rad / 2)**2) + (Math.cos(lat_rad_1) * Math.cos(lat_rad_2) * (Math.sin(delta_long_rad / 2)**2)))
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      d = r * c
    end
  end
end
