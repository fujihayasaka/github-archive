# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RequestReviewsByLogin < Platform::Mutations::Base
      include Platform::Mutations::Shared::RequestReviews

      class ParsedTeam < T::Struct
        const :org_login, String
        const :team_slug, String
        const :full_slug, String
      end

      description "Set review requests on a pull request using login strings instead of IDs."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "The Node ID of the pull request to modify.", required: true, loads: Objects::PullRequest, as: :pull
      argument :user_logins, [String], "The login strings of the users to request reviews from.", required: false
      argument :bot_logins, [String], "The logins of the bots to request reviews from, including the [bot] suffix (e.g., 'copilot-pull-request-reviewer[bot]').", required: false
      argument :team_slugs, [String], "The slugs of the teams to request reviews from (format: 'org/team-slug').", required: false
      argument :union, Boolean, "Add users to the set rather than replace.", required: false, default_value: false
      argument :re_request, Boolean, "Whether or not the request is a re-request", required: false, default_value: false, visibility: :internal

      field :requested_reviewers_edge, Edges::User, "The edge from the pull request to the requested reviewers.", null: true

      field :pull_request, Objects::PullRequest, "The pull request that is getting requests.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull:, **inputs)
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(:request_pull_request_review, repo: repo, resource: pull, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull:, user_logins: nil, bot_logins: nil, team_slugs: nil, union: false, re_request: false)
        resolve_reviewers_from_logins(
          pull: pull,
          user_logins: user_logins,
          bot_logins: bot_logins,
          team_slugs: team_slugs,
          union: union,
          re_request: re_request
        )
      end

      private

      def resolve_reviewers_from_logins(pull:, user_logins: nil, bot_logins: nil, team_slugs: nil, union: false, re_request: false)
        user_logins_array = Array.wrap(user_logins)
        bot_logins_array = Array.wrap(bot_logins)
        team_slugs_array = Array.wrap(team_slugs)

        # Parse and validate team slug format before making any database calls
        # Team slugs are in format 'org/team-slug'
        # There is no way to load a team without knowing its org first, so we need to split them
        # and independently load the orgs first
        parsed_teams = team_slugs_array.map do |slug|
          unless slug.include?("/")
            raise Errors::Unprocessable.new("Team slug '#{slug}' must be in the format 'org/team-slug'.")
          end
          org_login, team_slug = slug.split("/", 2)
          ParsedTeam.new(org_login: org_login, team_slug: team_slug, full_slug: slug)
        end

        # Use case-insensitive lookups to handle logins passed with different casing
        # (e.g., "monalisa" matching "MonaLisa").
        #
        # Additionally, downcase logins before querying to work around a separate issue in
        # User::UserLoginType#serialize (packages/users/app/models/user/user_login_type.rb).
        # In multi-tenant (EMU) mode, serialize calls User.unique_tenant_login?
        # (packages/users/app/models/user.rb) which does a case-sensitive end_with?
        # check for the tenant shortcode suffix. An uppercased login like "USER_SUFFIX"
        # fails that check and gets the suffix double-appended, producing a login
        # that doesn't exist in the database.
        user_logins_array = user_logins_array.map(&:downcase)
        users_promise = Loaders::ActiveRecord.load_all(::User, user_logins_array, column: :login, case_sensitive: false)
        bots_promise = build_bots_promise(bot_logins_array)

        org_logins = parsed_teams.map { |pt| pt.org_login.downcase }.uniq
        orgs_promise = Loaders::ActiveRecord.load_all(::Organization, org_logins, column: :login, case_sensitive: false)

        Promise.all([users_promise, bots_promise, orgs_promise]).then do |users, bots, orgs|
          orgs_by_login = org_logins.zip(orgs).to_h
          teams_promise = build_teams_promise(parsed_teams, orgs_by_login)

          teams_promise.then do |teams|
            reviewers = build_reviewers(
              user_logins_array:, users:,
              bot_logins_array:, bots:,
              parsed_teams:, teams:
            )

            resolve_request_reviews(
              pull:,
              reviewers:,
              re_request: re_request,
              union: union
            )
          end
        end
      end

      # Bot logins are expected to include the [bot] suffix (e.g., "my-app[bot]")
      # We also try to look up by Integration slug (without the suffix) as a fallback
      def build_bots_promise(bot_logins_array)
        bot_slugs_for_integration_lookup = bot_logins_array.map { |login| login.gsub(/\[bot\]\z/, "") }

        bots_by_login_promise = Loaders::ActiveRecord.load_all(::Bot, bot_logins_array, column: :login)
        bots_by_slug_promise = Loaders::ActiveRecord.load_all(::Integration, bot_slugs_for_integration_lookup, column: :slug).then do |integrations|
          integrations.map { |integration| integration&.bot }
        end

        Promise.all([bots_by_login_promise, bots_by_slug_promise]).then do |bots_by_login, bots_by_slug|
          bot_logins_array.each_index.map do |index|
            bots_by_login[index] || bots_by_slug[index]
          end
        end
      end

      def build_teams_promise(parsed_teams, orgs_by_login)
        team_promises = parsed_teams.map do |parsed|
          org = orgs_by_login[parsed.org_login.downcase]
          if org.nil?
            Promise.resolve(nil)
          else
            Loaders::TeamBySlug.load(org, parsed.team_slug)
          end
        end

        Promise.all(team_promises)
      end

      def build_reviewers(user_logins_array:, users:, bot_logins_array:, bots:, parsed_teams:, teams:)
        reviewers = []

        user_logins_array.zip(users).each do |login, user|
          raise Errors::NotFound, "Could not resolve user with login '#{login}'." if user.nil? || user.is_a?(Bot)
          reviewers << user
        end

        bot_logins_array.zip(bots).each do |slug, bot|
          raise Errors::NotFound.new("Could not resolve bot with slug '#{slug}'.") if bot.nil?
          reviewers << bot
        end

        parsed_teams.zip(teams).each do |parsed, team|
          raise Errors::NotFound.new("Could not resolve team with slug '#{parsed.full_slug}'.") if team.nil?
          reviewers << team
        end

        reviewers
      end
    end
  end
end
