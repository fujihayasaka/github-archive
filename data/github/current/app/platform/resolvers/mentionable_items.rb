# typed: false
# frozen_string_literal: true

module Platform
  module Resolvers
    class MentionableItems < Resolvers::Base
      # setting to 10k because the 1k limit set in the mentionable_users_for method omits a number
      # of users for orgs with more than 1k members
      MENTIONABLES_LIMIT = 10_000

      argument :query, String, "Filters users, teams with query on mentionable items", required: false

      type Connections.define(Unions::MentionableItem), null: false

      def resolve(query: nil)
        query_string = ActiveRecord::Base.sanitize_sql_like(
          query.to_s.strip.downcase,
        )
        async_users = async_users(query_string: query_string)
        async_teams = async_teams(query_string: query_string)

        Promise.all([async_users, async_teams]).then do |users, teams|
          ArrayWrapper.new(users + teams)
        end
      end

      private

      def async_users(query_string:)
        # we skip on making performing a search for users when the query_string include "/"
        # because the assumption is that they are searching for a team within the org.
        # eg. query_string="github/mobile"
        return [] if query_string.include?("/")

        Promise.all([async_participant_ids, async_mentionable_user_ids]).then do |participant_ids, mentionable_user_ids|
          # the hope here is to bump up immediate participants of the issue/pull and the collaborators(User) on the
          # repository
          user_ids = participant_ids.concat(mentionable_user_ids) - context[:viewer].ignored_by.pluck(:id)
          user_ids.uniq!
          users = User.where(id: user_ids)
          scope = users.filter_spam_for(context[:viewer]).not_suspended

          if scope && query_string.present?
            scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                         .where(["users.login LIKE ? OR profiles.name LIKE ?", "%#{query_string}%", "%#{query_string}%"])
          end

          # sort scope by order of user_ids used to build to scope
          scope_by_ids = scope.index_by(&:id)
          user_ids.map { |uid| scope_by_ids[uid] }.compact
        end
      end

      def async_mentionable_user_ids
        object.async_repository.then do |repo|
          Promise.all([repo.async_parent, repo.async_owner]).then do |_parent, owner|
            if owner.organization?
              Platform::Loaders::Configuration.load(owner, :default_repository_permission)
            end
          end.then do
            mention_ids = repo.mentionable_users_for(context[:viewer], fields: ["users.id"], limit: MENTIONABLES_LIMIT).pluck("users.id")
            # bump up immediate collaborators on the repository
            repo.all_member_ids.concat(mention_ids).uniq
          end
        end
      end

      def async_participant_ids
        if object.is_a?(PullRequest)
          Loaders::ActiveRecord.load(::Issue, object.id, column: :pull_request_id).then do |_issue|
            Promise.all([object.async_base_repository,
                         object.async_user,
                         object.async_commenters,
                         object.async_changed_commits]).then do |_repository, _|
              object.participants_for(context[:viewer], optimize_repo_access_checks: true, remove_dependabot: false).map(&:id)
            end
          end
        else
          Promise.all([object.async_user, object.async_commenters]).then do
            object.participants_for(context[:viewer], optimize_repo_access_checks: true).map(&:id)
          end
        end
      end

      def async_teams(query_string:)
        object.async_repository.then do |repo|
          repo.async_organization.then do |org|
            next [] unless org

            org.async_teams.then do
              # query string can include "/" which would signify a user trying to query for a specific team
              # within their org
              if query_string.include?("/")
                org_name, team_name = query_string.split("/")
                sql = "users.login LIKE ? AND (teams.name LIKE ? OR teams.slug LIKE ?)"
              else
                org_name = query_string
                team_name = query_string
                sql = "users.login LIKE ? OR teams.name LIKE ? OR teams.slug LIKE ?"
              end

              teams = org.visible_teams_for(context[:viewer])
              teams.joins("LEFT JOIN users ON users.id = teams.organization_id")
                   .where(sql, "%#{org_name}%", "%#{team_name}%", "%#{team_name}%")
            end
          end
        end
      end
    end
  end
end
