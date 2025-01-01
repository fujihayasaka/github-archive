# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryAdminInfo < Platform::Objects::Base
      description "Repository information only visible to members"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.repo.adminable_by?(permission.viewer)
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      field :collaborators, Connections::User, description: "A list of collaborators affiliated with the repository.", null: false, connection: true do
        argument :affiliations, [Enums::RepositoryCollaboratorAffiliation], "Filtering option for collaborators by affiliation.", required: false
      end

      def collaborators(**arguments)
        context[:permission].async_can_list_collaborators?(object.repo).then do |can_list_collabs|
          if !can_list_collabs
            ::User.none
          else
            repo = @object.repo

            repo.async_organization.then do
              if arguments[:affiliations] && (arguments[:affiliations].first == "outside")
                users = repo.members
                users = users - repo.organization.members if repo.in_organization?
                users
              else
                if repo.in_organization?
                  Platform::Loaders::Configuration.load(repo.organization, :default_repository_permission).then do |permission|
                    org_visible_users = if permission != :none
                      repo.organization.visible_users_for(@context[:viewer], type: :all)
                    else
                      []
                    end
                    org_visible_users + repo.members + repo.all_team_members(include_org_admins: true)
                  end
                else
                  repo.members + [repo.owner]
                end
              end
            end.then do |users|
              users ||= []
              ArrayWrapper.new(users.to_a.uniq)
            end
          end
        end
      end
    end
  end
end
