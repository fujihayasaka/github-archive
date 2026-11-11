# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class ActorLocation < Platform::Objects::AuditLog::Base
        description "Location information for an actor"

        scopeless_tokens_as_minimum


        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          permission.async_api_can_access_audit_entry?(audit_entry).then do |can_access|
            can_access || permission.viewer&.site_admin?
          end
        end

        # This object is backed by Hashes and cannot be fetched by node id. It
        # relies on the parent object for permission checks.
        def self.async_viewer_can_see?(permission, audit_entry)
          permission.async_viewer_can_see_audit_entry?(audit_entry).then do |can_access|
            can_access || permission.viewer&.site_admin?
          end
        end

        field :country_code, String, null: true, description: "Country code"
        def country_code
          actor_location["country_code"]
        end

        field :country, String, null: true, description: "Country name"
        def country
          actor_location["country_name"]
        end

        field :region_code, String, null: true, description: "Region or state code"
        def region_code
          if viewer_is_actor?
            actor_location["region"]
          end
        end

        field :region, String, null: true, description: "Region name"
        def region
          if viewer_is_actor?
            actor_location["region_name"]
          end
        end

        field :city, String, null: true, description: "City"
        def city
          if viewer_is_actor?
            actor_location["city"]
          end
        end

        field :postal_code, String, null: true, visibility: :internal, description: "Postal or ZIP code"
        def postal_code
          actor_location["postal_code"]
        end

        field :latitude, Float, null: true, visibility: :internal, description: "Latitude"
        def latitude
          actor_location.dig("location", "lat")
        end

        field :longitude, Float, null: true, visibility: :internal, description: "Longitude"
        def longitude
          actor_location.dig("location", "lon")
        end

        private

        def viewer_is_actor?
          context[:viewer].id == @object.get(:actor_id)
        end

        def actor_ip
          @object.get(:actor_ip)
        end

        def actor_ip_is_external?
          actor_ip && actor_ip != "127.0.0.1" && actor_ip != "::1"
        end

        def actor_location
          @actor_location ||= if @object.get(:actor_location).present?
            @object.get(:actor_location)
          elsif actor_ip_is_external?
            GitHub.dogstats.increment("audit.entry.location.lookup")
            GitHub::Location.look_up(actor_ip)
          else
            {}
          end
        end
      end
    end
  end
end
