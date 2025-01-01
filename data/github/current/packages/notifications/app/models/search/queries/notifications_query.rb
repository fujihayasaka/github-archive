# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class NotificationsQuery < ::Search::Query
      def self.field_list
        [:is, :reason, :repo, :author, :org].freeze
      end
      UNSUPPORTED_IS_VALUES = %w[issue pr pull-request].freeze

      VALID_INBOX_TABS_VIEWS_HYPERLIST = ["view:focusing", "view:team_mention", "view:not_focus_team_mention"].freeze

      VALID_INBOX_TABS_VIEWS_CLIENT_APPS = ["view:client_apps_important"].freeze

      VALID_INBOX_ONLY_QUERIES = [
        "",
        "is:unread is:read",
        "is:read is:unread",
        "is:unread",
      ].freeze

      # Maps the qualifier strings to the value stored in the document
      TYPE_QUALIFIER_MAPPINGS = {
        "check-suite"                    => "CheckSuite",
        "commit"                         => "Commit",
        "gist"                           => "Gist",
        "issue"                          => "Issue",
        "pr"                             => "PullRequest",
        "pull-request"                   => "PullRequest",
        "release"                        => "Release",
        "repository-invitation"          => "RepositoryInvitation",
        "repository-vulnerability-alert" => "RepositoryVulnerabilityAlert",
        "repository-advisory"            => "RepositoryAdvisory",
        "team-discussion"                => "DiscussionPost",
        "discussion"                     => "Discussion",
      }

      attr_reader :parsed, :query, :viewer

      def initialize(query:, viewer:)
        @query = (query || "").strip
        @viewer = viewer
        @parsed = parsed_query_value
      end

      def parsed_query_value
        ParsedQuery.parse(@query, terms: qualifier_fields)
      end

      # Is the query string one which is considered an "inbox" query
      def is_only_an_inbox_query?
        VALID_INBOX_ONLY_QUERIES.include?(query)
      end

      def read?
        return @read if defined? @read

        @read = qualifier_values(:is).any?("read")
      end

      def unread?
        return @unread if defined? @unread

        @unread = qualifier_values(:is).any?("unread")
      end

      def starred?
        return @starred if defined? @starred

        @starred = qualifier_values(:is).any?("saved")
      end

      def archived?
        return @archived if defined? @archived

        @archived = qualifier_values(:is).any?("done")
      end

      def thread_type?
        return @thread_type if defined? @thread_type

        @thread_type = qualifier_values(:is).any? { |v| !%w[read unread done].include?(v) }
      end

      def participating?
        return @participating if defined? @participating

        @participating = qualifier_values(:reason).any?("participating")
      end

      def qualifier_used?(qualifier)
        qualifier_values(qualifier).any?
      end

      def contains_unsupported_qualifiers?
        query.gsub(/(#{qualifier_fields.join("|")}):\S+/, "").strip.present?
      end

      # Is supported by mysql if it doesn't contain any unsupported qualifiers
      # and it doesn't contain is:issue, is:pr, etc
      def supported_by_mysql?
        !contains_unsupported_qualifiers? && !qualifier_values(:is).any? { |value| UNSUPPORTED_IS_VALUES.include?(value) }
      end

      def stringify(unread: unread?, read: read?, archived: archived?, starred: starred?, reasons: nil, repositories: nil, repository_names: nil)
        new_query = parsed.dup

        if read && unread && !archived
          # Here the user wants all their non-archived notifications (both read and unread) which is
          # the default so remove some unnecessary qualifiers.
          new_query = toggle_qualifier(new_query, :is, "read", false)
          new_query = toggle_qualifier(new_query, :is, "unread", false)
        else
          new_query = toggle_qualifier(new_query, :is, "read", read)
          new_query = toggle_qualifier(new_query, :is, "unread", unread)
        end

        new_query = toggle_qualifier(new_query, :is, "done", archived)

        new_query = toggle_qualifier(new_query, :is, "saved", starred)

        if reasons
          new_query = replace_qualifiers(new_query, :reason, reasons)
        end

        if repositories
          name_with_owners = repositories.map(&:name_with_owner)
          new_query = replace_qualifiers(new_query, :repo, name_with_owners)
        end

        if repository_names
          new_query = replace_qualifiers(new_query, :repo, repository_names)
        end

        new_query.uniq!

        self.class.stringify(new_query)
      end

      def statuses
        return @statuses if defined? @statuses

        @statuses = []
        @statuses << "read" if read?
        @statuses << "unread" if unread?
        @statuses << "archived" if archived?

        @statuses = %w[read unread] if @statuses.empty?
        @statuses
      end

      # Get an array of valid reasons for the specified reason: qualifiers.
      def reasons
        return @reasons if defined? @reasons

        return Newsies::NotificationEntry::PARTICIPATING_REASONS if participating?

        reasons = qualifier_values(:reason)
                    .map { |reason| reason.gsub(/-/, "_") }
                    .select { |reason| Platform::Enums::NotificationReason.values.include?(reason.upcase) }
        @reasons = reasons.map(&:downcase)
      end

      def thread_types
        return @thread_types if defined? @thread_types

        is_values = qualifier_values(:is) || []

        @thread_types = is_values.map do |key|
          key = "issue" if %w[issue-or-pull-request issue-or-pr].include?(key)
          thread_type = TYPE_QUALIFIER_MAPPINGS[key]
          next "Issue" if thread_type == "PullRequest"
          thread_type
        end.compact

        # If user has passed in the is:repository-vulnerability-alert filter, we
        # should return notifications threads for RepositoryDependabotAlertsThread and SecurityAdvisory
        # in additon to the RepositoryVulnerabilityAlert thread. This move allows us to not introduce any new filter
        # while we gradually phase out RepositoryVulnerabilityAlert notification threads
        if @thread_types.include?("RepositoryVulnerabilityAlert")
          @thread_types += %w[RepositoryDependabotAlertsThread SecurityAdvisory]
        end

        @thread_types
      end

      # Get an array of Repository objects for the specified repo: qualifiers
      def repositories
        return @repositories if defined? @repositories

        repositories = qualifier_values(:repo).map do |name_with_owner|
          repository = Repository.with_name_with_owner(name_with_owner)
          next if repository.nil?
          next unless repository.readable_by?(viewer)
          repository
        end

        @repositories = repositories.compact
      end

      def owners
        @owners ||= User.where(login: qualifier_values(:org))
      end

      def authors
        @authors ||= User.with_logins(author_logins_from_qualifier)
      end

      # Hyperlist inbox tabs views
      def valid_inbox_tab_view?
        VALID_INBOX_TABS_VIEWS_HYPERLIST.any? { |view| query.include?(view) }
      end

      def focusing?
        valid_inbox_tab_view? && query.include?("view:focusing")
      end

      def team_mention?
        valid_inbox_tab_view? && !focusing? && query.include?("view:team_mention")
      end

      def not_focus_team_mentioned?
        valid_inbox_tab_view? && !team_mention? && !focusing? && query.include?("view:not_focus_team_mention")
      end

      # Client Apps inbox tab views
      def valid_client_apps_inbox_tab_view?
        VALID_INBOX_TABS_VIEWS_CLIENT_APPS.any? { |view| query.include?(view) }
      end

      def client_apps_important?
        valid_client_apps_inbox_tab_view? && query.include?("view:client_apps_important")
      end

      private

      # Private: returns valid login strings from qualifier.
      #
      # Bot logins are stored in the `users` table as `login[bot]`.
      # However, bots logins via the client are represented as `app/loin`.
      # For more details: https://github.com/github/github/blob/8cafb33b61402ac134d12950a3e0dcd27cc2ab0b/app/models/bot.rb#L61-L75
      #
      # This means if the user passes a login such as app/github-heaven,
      # we need to remove the `app/` string and append `[bot]` to the login.
      # before we search the users table.
      #
      # returns Array<string>
      def author_logins_from_qualifier
        qualifier_values(:author).map do |login|
          login = login.downcase

          # Convert `author:app/login` to `login[bot]` so we find Bot users in
          # the same query as other users.
          login.match(%r{\Aapp/(.+)}) do |m|
            login = "#{m[1]}#{Bot::LOGIN_SUFFIX}"
          end

          login
        end.compact
      end

      def toggle_qualifier(query, name, value, state)
        new_query = query.dup

        if state
          new_query << [name, value] unless new_query.include?([name, value])
        else
          new_query.reject! do |component|
            matches_qualifier?(component, name, value)
          end
        end

        new_query
      end

      def qualifiers
        @qualifiers ||= parsed.select { |component| qualifier?(component) }
      end

      def qualifier_values(name)
        values = qualifiers.select do |component|
          component.first == name
        end
        values.map(&:second)
      end

      def qualifier?(component)
        # Select non-negated qualifiers such as qualifier:value
        component.is_a?(Array) && component.third != true
      end

      def matches_qualifier?(component, name, value)
        qualifier?(component) && component.first == name && value.casecmp?(component.second)
      end

      def replace_qualifiers(query, name, values)
        new_query = query.reject { |component| component.first == name }
        values.each { |value| new_query << [name, value] }
        new_query
      end
    end
  end
end
