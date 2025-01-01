# typed: true
# frozen_string_literal: true

module Configurable
  module CodespaceDefaultLocation
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceLocation < ArgumentError; end

    KEY = "codespace_default_location"

    def codespace_default_location
      location = config.get(KEY)
      Codespaces::Locations::Geo.public.where(primary_region: location).blank? ? nil : location
    end

    def update_codespace_default_location(location, force = false, actor:)
      raise InvalidCodespaceLocation unless Codespaces::Settings::VALID_LOCATIONS.include?(location) || location.nil?

      changed = if location.nil?
        config.delete(KEY, actor)
      else
        config.set!(KEY, location, actor, force)
      end
      return unless changed

      GitHub.dogstats.increment("codespace_default_location.updated")
    end
  end
end
