# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TeamBySlug < Platform::Loader

      # Loads a single team on an organization by its slug.
      #
      # user - Optional User. If given, ensures that the loaded team is visible to the user. When
      #        this method is used directly by a caller, the user argument should be omitted and
      #        visibility should be checked using Team#async_visible_to? instead to improve
      #        performance for use case of loading a single team. Regardless, whenever the user
      #        argument is omitted the caller is responsible for authorization checks.
      #
      # Returns a Promise of Team.
      def self.load(organization, team_slug)
        self.for(organization).load(team_slug.downcase)
      end

      # Loads a list of teams on an organization by their slugs.
      #
      # user - Optional User. If given, ensures that the loaded teams are visible to the user. If
      #        omitted, the caller is responsible for authorization checks.
      #
      # Returns a Promise of Array<Team>.
      def self.load_all(organization, team_slugs)
        loader = self.for(organization)
        Promise.all(
          team_slugs
          .map(&:downcase)
          .map { |team_slug| loader.load(team_slug) },
        )
      end

      def initialize(organization)
        @organization = organization
      end

      private def fetch(team_slugs)
        @organization.teams.where(slug: team_slugs).index_by(&:slug)
      end
    end
  end
end
