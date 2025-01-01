# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class RepositoriesComponent < ApplicationComponent
      REPOSITORY_MAX_RESULTS = 5

      attr_reader :organization

      def initialize(organization:)
        @organization = organization
      end

      def render?
        organization&.adminable_by?(current_user) && Onboarding::Organization.new(organization).enabled?
      end

      memoize def show_view_all_repositories?
        organization.repositories.count > REPOSITORY_MAX_RESULTS
      end

      def repositories
        repository_preloads = [:primary_language]
        repositories = organization.repositories
          .preload(repository_preloads)
          .recently_updated
          .limit(REPOSITORY_MAX_RESULTS)
      end
    end
  end
end
