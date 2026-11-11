# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BusinessTeamBySlugWithOrganizationContext < Platform::Loader
      # Public: Loads a single BusinessTeam by slug within the context of an organization.
      # The team must belong to the org's enterprise and be assigned to the org.
      #
      # Expects slugs WITH the "ent:" prefix (e.g. "ent:my-team"). The prefix
      # is what distinguishes a BusinessTeam slug from an Organization Team slug,
      # preventing name collisions.
      #
      # organization - The Organization providing the context for the lookup.
      # team_slug    - The slug including the "ent:" prefix.
      #
      # Returns a Promise of BusinessTeam or nil.
      sig { params(organization: Organization, team_slug: String).returns(Promise[T.nilable(BusinessTeam)]) }
      def self.load(organization, team_slug)
        self.for(organization).load(team_slug.downcase)
      end

      sig { params(organization: Organization).void }
      def initialize(organization)
        @organization = organization
      end

      sig { params(team_slugs: T::Array[String]).returns(T.any(T::Hash[String, BusinessTeam], Promise[T::Hash[String, BusinessTeam]])) }
      private def fetch(team_slugs)
        membership = Business::OrganizationMembership.find_by(organization_id: @organization.id)
        return {} if membership.nil?

        # The DB stores slugs without the "ent:" prefix, but BusinessTeam#slug
        # re-adds it. Strip the prefix for the query, then index by the
        # full prefixed slug so the loader cache key matches.
        model_slugs = team_slugs.map { |s| BusinessTeam.to_model_slug(s) }

        candidates = BusinessTeam.where(business_id: membership.business_id, slug: model_slugs)
        return {} if candidates.empty?

        # Filter to only teams assigned to this organization using the domain
        Orgs.domain.teams.async_business_team_ids_for_assigned_orgs(
          organization_id: @organization.id,
          team_ids: candidates.map(&:id),
        ).then do |assigned_ids|
          assigned_set = assigned_ids.to_set
          candidates
            .select { |bt| assigned_set.include?(bt.id) }
            .each { |bt| bt.set_organization_context(@organization, check_association: false) }
            .index_by { |bt| bt.slug.downcase }
        end
      end
    end
  end
end
