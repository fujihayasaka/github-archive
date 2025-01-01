# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Location < Platform::Objects::Base
      description "Location information for an actor"
      visibility :under_development
      scopeless_tokens_as_minimum


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # This object is backed by Hashes and cannot be fetched by node id. It
      # relies on the parent object for permission checks.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :country_code, String, null: true, description: "Country code"
      field :country_name, String, null: true, description: "Country name"
      field :region, String, null: true, description: "Region or state code"
      field :region_name, String, null: true, description: "Region name"
      field :city, String, null: true, description:  "City"
      field :postal_code, String, null: true, description: "Postal or ZIP code"

      field :latitude, Float, null: true, description: "Latitude"
      def latitude
        @object["location"]["lat"]
      end

      field :longitude, Float, null: true, description: "Longitude"
      def longitude
        @object["location"]["lon"]
      end
    end
  end
end
