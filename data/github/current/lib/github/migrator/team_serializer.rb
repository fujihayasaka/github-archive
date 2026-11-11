# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class TeamSerializer < BaseSerializer
      def scope
        Team.preload(:organization)
      end

      def as_json(options = {})
        {
          type:         "team",
          url:          url,
          organization: organization,
          parent_team:  parent_team,
          name:         name,
          description:  description,
          privacy:      privacy,
          permissions:  permissions, # based on abilities, N+1
          members:      members, # based on abilities, N+1
          created_at:   created_at,
        }
      end

      private

      def name
        model.name
      end

      def description
        model.description
      end

      def privacy
        model.privacy.to_s
      end

      def parent_team
        url_for_model(model.parent_team)
      end

      def organization
        url_for_model(model.organization)
      end

      def permissions
        model.repositories.map do |repo|
          {
            repository: url_for_model(repo),
            access: model.permission_for(repo),
            role: repo.direct_role_for(model).to_s
          }
        end
      end

      def members
        # Skip exporting members when org metadata only, as it's not needed for now.
        return [] if org_metadata_only
        model.members.map do |user|
          {
            user: url_for_model(user),
            role: model.maintainer?(user) ? "maintainer" : "member",
          }
        end
      end
    end
  end
end
