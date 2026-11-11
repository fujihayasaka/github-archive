# typed: strict
# frozen_string_literal: true

module Copilot
  module Chat
    # Encapsulates the repository search logic for Copilot Chat.
    # Handles smart search with owner extraction, user login detection, and top repo prioritization.
    class RepositorySearch
      include GitHub::Memoizer

      DEFAULT_LIMIT = 10

      sig { returns(::User) }
      attr_reader :user

      sig { returns(T.nilable(::UserSession)) }
      attr_reader :user_session

      sig { returns(T.nilable(String)) }
      attr_reader :remote_ip

      sig { returns(ConditionalAccess::Filter) }
      attr_reader :cap_filter

      sig do
        params(
          user: ::User,
          user_session: T.nilable(::UserSession),
          remote_ip: T.nilable(String),
          cap_filter: ConditionalAccess::Filter
        ).void
      end
      def initialize(user:, user_session:, remote_ip:, cap_filter:)
        @user = user
        @user_session = user_session
        @remote_ip = remote_ip
        @cap_filter = cap_filter
      end

      # Main entry point for searching repositories
      sig do
        params(
          query: String,
          limit: T.nilable(Integer),
          include_forks: T::Boolean,
          current_repo_id: T.nilable(Integer),
          owner: T.nilable(String)
        ).returns(T::Array[Repository])
      end
      def search(query:, limit: nil, include_forks: false, current_repo_id: nil, owner: nil)
        limit = [[(limit || DEFAULT_LIMIT), 1].max, DEFAULT_LIMIT].min

        # If owner is specified (e.g., for org-owned spaces), scope search to that owner
        if owner.present?
          return search_by_owner(query, owner, limit, include_forks: false)
        end

        top_repos = top_repositories(limit: limit)
        top_repo_ids = Set.new(top_repos.map(&:id))

        if query.blank?
          prepend_current_repo(top_repos, current_repo_id)
        else
          smart_search(query, top_repos, top_repo_ids, limit, include_forks: include_forks)
        end.first(limit)
      end

      # Search repositories scoped to a specific owner (used for org-owned spaces)
      sig do
        params(
          query: String,
          owner_login: String,
          limit: Integer,
          include_forks: T::Boolean
        ).returns(T::Array[Repository])
      end
      def search_by_owner(query, owner_login, limit, include_forks: false)
        search_repositories(query.presence || "", owner_login, limit, include_forks: include_forks).first(limit)
      end

      private

      # Smart search that handles owner extraction and user login detection
      sig do
        params(
          query: String,
          top_repos: T::Array[Repository],
          top_repo_ids: T::Set[Integer],
          limit: Integer,
          include_forks: T::Boolean
        ).returns(T::Array[Repository])
      end
      def smart_search(query, top_repos, top_repo_ids, limit, include_forks: false)
        # Check if query has "owner/repo" format (with actual content after the slash)
        if query.include?("/")
          owner_part, repo_part = query.split("/", 2).map(&:strip)
          owner_part = owner_part.presence || ""
          repo_part = repo_part.presence || ""
          if owner_part.present?
            return search_and_sort_by_top_repos(repo_part, owner_part, top_repo_ids, limit, include_forks: include_forks)
          end

          # remove trailing slash if repo_part is blank, treating "owner/" as "owner"
          if !repo_part.present?
            query = owner_part
          end
        end

        matching_top_repos = get_matching_top_repos(query, top_repos)
        return matching_top_repos if matching_top_repos.size >= limit

        # Check if query starts with current user's login
        user_login = user.display_login.downcase
        search_results = []

        if query.downcase.start_with?("#{user_login}/", user_login)
          # Search user's repos with cleaned query (without the username prefix)
          cleaned_query = query.sub(/\A#{Regexp.escape(user_login)}\/?/i, "").strip
          user_repos = search_repositories(cleaned_query.presence || query, user_login, limit, include_forks: include_forks)
          search_results.concat(user_repos)
        end

        # Search all repos with original query
        all_repos = search_repositories(query, nil, limit, include_forks: include_forks)
        search_results.concat(all_repos)

        # Deduplicate
        search_results = search_results.uniq(&:id)

        # Merge: matching top repos first, then search results (with top repos prioritized)
        merge_with_top_repo_priority(matching_top_repos, search_results, top_repo_ids)
      end

      sig { params(query: String, top_repos: T::Array[Repository]).returns(T::Array[Repository]) }
      def get_matching_top_repos(query, top_repos)
        lower_query = query.downcase
        top_repos.select { |r| r.name_with_display_owner.downcase.include?(lower_query) }
      end

      sig do
        params(
          query: String,
          owner: T.nilable(String),
          top_repo_ids: T::Set[Integer],
          limit: Integer,
          include_forks: T::Boolean
        ).returns(T::Array[Repository])
      end
      def search_and_sort_by_top_repos(query, owner, top_repo_ids, limit, include_forks: false)
        repos = search_repositories(query, owner, limit, include_forks: include_forks)

        # Sort: repos in top_repos first, then others
        in_top = repos.select { |r| top_repo_ids.include?(r.id) }
        not_in_top = repos.reject { |r| top_repo_ids.include?(r.id) }
        in_top + not_in_top
      end

      sig do
        params(
          matching_top_repos: T::Array[Repository],
          search_results: T::Array[Repository],
          top_repo_ids: T::Set[Integer]
        ).returns(T::Array[Repository])
      end
      def merge_with_top_repo_priority(matching_top_repos, search_results, top_repo_ids)
        result = matching_top_repos.dup
        seen_ids = Set.new(result.map(&:id))

        # Add search results that are in top repos (but not already added)
        search_results.each do |repo|
          next if seen_ids.include?(repo.id)
          if top_repo_ids.include?(repo.id)
            result << repo
            seen_ids.add(repo.id)
          end
        end

        # Add remaining search results
        search_results.each do |repo|
          next if seen_ids.include?(repo.id)
          result << repo
          seen_ids.add(repo.id)
        end

        result
      end

      sig { params(repos: T::Array[Repository], current_repo_id: T.nilable(Integer)).returns(T::Array[Repository]) }
      def prepend_current_repo(repos, current_repo_id)
        return repos unless current_repo_id

        # Check if current repo is already in the list
        return repos if repos.any? { |r| r.id == current_repo_id }

        # Try to find and prepend the current repo
        current_repo = cap_filter.evaluate(Repository.where(id: current_repo_id)).authorized.resources.first
        return repos unless current_repo

        [current_repo] + repos
      end

      sig do
        params(
          query: String,
          owner: T.nilable(String),
          limit: Integer,
          include_forks: T::Boolean
        ).returns(T::Array[Repository])
      end
      def search_repositories(query, owner = nil, limit = DEFAULT_LIMIT, include_forks: false)
        search_query = Search::Queries::RepoQuery.new(
          current_user: user,
          user_session: user_session,
          remote_ip: remote_ip,
          phrase: build_search_phrase(query, include_forks: include_forks),
          include_forks: include_forks,
          per_page: limit,
          page: 1,
          cap_filter: cap_filter,
        )

        if owner.present?
          search_query.qualifiers[:org].clear.must [owner]
        end

        results = search_query.execute
        results.results.map { |r| r["_model"] }.compact
      end

      sig { params(limit: Integer).returns(T::Array[Repository]) }
      def top_repositories(limit:)
        TopRepositories.for(viewer: user, since: 1.year.ago, cap_filter: cap_filter).limit(limit).to_a
      end

      sig { params(query: String, include_forks: T::Boolean).returns(String) }
      def build_search_phrase(query, include_forks: false)
        fork_qualifier = include_forks ? "fork:true" : ""
        "#{query.strip} in:name archived:false #{fork_qualifier}".strip.gsub(/\s+/, " ")
      end
    end
  end
end
