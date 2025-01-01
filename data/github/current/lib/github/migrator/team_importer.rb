# typed: true
# frozen_string_literal: true

require "github/migrator/url_helpers"

module GitHub
  class Migrator
    class TeamImporter < Importer
      include UrlHelpers

      def import(attributes, options = {})
        team = Team.create! do |team|
          @organization = model_from_source_url!(attributes["organization"])

          team.organization = @organization

          @team_name = attributes["name"]
          team.name = @team_name
          team.description = attributes["description"]
          team.privacy = attributes["privacy"] || :secret
          team.created_at = attributes["created_at"]
          team.slug = team_slug(attributes)

          # If the team's slug conflicts with that of any other team in the org
          # (it shouldn't), use the generated unique slug instead of letting
          # this team fail import.
          if team.any_conflicting_slugs?(team.slug)
            team.slug = team.generate_unique_slug
          end

          # If the team's name conflicts with that of any other team in the org,
          # use the slug (which, after the last `if` block, is guaranteed to be
          # unique) as the team's new name.
          if !name_unique?
            @team_name = team.name = team.slug
          end

          parent_team = model_from_source_url(attributes["parent_team"])

          if can_be_nested?(team, parent_team)
            team.parent_team_id = parent_team.id
          end

          set_legacy_permissions(@organization, team, attributes["permissions"])

          team.save!
        end

        add_permissions(attributes["permissions"], team)
        add_members(attributes["members"], team)

        ImporterResult.new(team)
      rescue ActiveRecord::RecordInvalid => error
        raise unless error.message.include?("Name must be unique for this org")

        new_message = "Validation failed: Name (#{@team_name}) must be unique for this org (#{@organization.login})"
        error.message.gsub!(
          "Name must be unique for this org",
          new_message
        )

        log_and_create_importer_result(
          attributes,
          error,
          new_message,
          "team",
          "skipped"
        )
      end

      def merge(attributes, team)
        if set_legacy_permissions(team.organization, team, attributes["permissions"])
          team.save!
        end

        add_permissions(attributes["permissions"], team)
        add_members(attributes["members"], team)
        team
      end

      private

      def team_slug(attributes)
        url_translator.extract(model_url_template("team", attributes), attributes["url"])["team"].parameterize
      end

      def can_be_nested?(team, parent_team)
        return unless parent_team
        [team, parent_team].none?(&:secret?)
      end

      def add_permissions(permissions, team)
        permissions.each do |permission|
          if repo = model_from_source_url(permission["repository"])
            # Note that passing the access permission to Team#add_repository is
            # a noop if the organization does not have direct org membership
            # enabled. See TeamImporter#set_legacy_permissions for handling
            # downgrades from direct org membership to legacy team permissions.
            role = permission["role"].to_sym if permission["role"].present?
            perm = permission["access"].to_sym

            if role
              begin
                team.add_repository(repo, role)
              rescue ActiveRecord::RecordInvalid
                team.add_repository(repo, perm)
              end
            else
              team.add_repository(repo, perm)
            end
          end
        end
      end

      def add_members(members, team)
        members.each do |member|
          if user = model_from_source_url(member["user"])
            next if user.ghost? || user.mannequin?
            team.add_member(user)

            if member["role"] == "maintainer"
              team.promote_maintainer(user)
            end
          end
        end
      end

      # Public: This handles setting permissions for a team in relation to
      # direct org membership and legacy permissions.
      #
      # It essentially does nothing for legacy => legacy migrations since a team
      # will have a unique permission that applies to all of the repos it is
      # associated with.
      #
      # For migrations from a source with direct org membership enabled it
      # will set the team permission to the least permissive permission from the
      # array of repository and access permissions. This means extra work for an
      # administrator post migration as they will have to review permissions,
      # but that feels like a better option than being more permissive and
      # possibly causing a security or compliance issue.
      #
      # When direct_org_membership is enabled for the organization on the
      # target this permission setter won't execute.
      #
      # organization - Organization instance the team belongs to.
      # team         - Team instance.
      # permissions  - Array of hashes with repository and access keys/values.
      #
      # Returns true if it sets legacy permission and false if it does not.
      def set_legacy_permissions(organization, team, permissions)
        false
      end

      def name_unique?
        @organization.teams.where(name: @team_name).none?
      end
    end
  end
end
