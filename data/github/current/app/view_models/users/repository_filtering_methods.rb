# typed: false
# frozen_string_literal: true

module Users
  module RepositoryFilteringMethods
    REPOSITORY_SORT_ORDERS = { "" => "Last updated", "name" => "Name", "stargazers" => "Stars" }.freeze

    # Public: Returns a hash of valid filters and their human-friendly names.
    def valid_type_filters(viewer: nil, user: nil, include_private:, include_internal: true)
      filters = {
        "all"    => "All",
        "public" => "Public"
      }

      if include_private
        filters["private"] = "Private"
      end

      if include_internal && user&.organization? && user.supports_internal_repositories? && viewer&.is_business_member?(user.business.id)
        filters["internal"] = "Internal"
      end

      filters = filters.merge(
        "source" => "Sources",
        "fork"   => "Forks",
        "archived" => "Archived",
      )

      filters["mirror"] = "Mirrors" if GitHub.mirrors_enabled?
      filters.delete("public") unless GitHub.public_repositories_available?

      filters["template"] = "Templates"

      filters
    end

    # Public: Returns a pretty name for the current filter, e.g., "Forks" for the filter "fork".
    def selected_type_filter(type:, types:)
      types[type] || "All"
    end

    # Public: Returns true if the specified type filter is valid for the user and the viewer.
    def type_filter_is_valid?(type:, types:)
      # The check for private-fork is temporary so we can introduce a query param for customers that will be affected
      # by org owned private forks
      type.blank? || types.key?(type) || type == "private-fork"
    end

    # Public: Returns a string for use in a phrase like "for X repositories".
    def type_filter_description(type)
      type == "fork" ? "forked" : type
    end

    # Public: Returns true if the user is searching or filtering repositories by a valid filter.
    def filtering_repositories?(type:, phrase:, language:, types:)
      return true if phrase.present? || language.present?
      type.present? && type_filter_is_valid?(type: type, types: types) && type != "all"
    end

    # Internal: Returns a sorted list of language names that occur in the
    # given repositories.
    def language_names_for(repos)
      LanguageName.where(
        id: repos.group(:primary_language_name_id).pluck(:primary_language_name_id),
      ).order(name: :asc).pluck(:name)
    end

    # Internal: Search repositories by phrase or language, from the perspective of the
    # authenticated user.
    def search_repos_as(current_user, page: 1, type: nil, types: nil, language: nil, sort_order: nil, repositories_scope: Repository)
      query_type = "Repositories"
      search_type = type == "all" ? nil : type
      queries = Search::QueryHelper.new(search_phrase(type: search_type, types: types), query_type,
        current_user: current_user,
        highlight: false,
        page: page,
        sort: search_sort(sort_order),
        language: language,
        per_page: Repository.per_page,
        user_session: user_session,
        cap_filter: cap_filter,
      )
      query = queries[query_type]

      query.qualifiers[:user].clear.must user.display_login

      search_results = query.execute
      repo_ids = search_results.map { |result| result.id.to_i }
      repos = repositories_scope.where(id: repo_ids)
      repos = case sort_order
      when "name"
        repos.sorted_by_name
      when "stargazers"
        repos.most_starred
      else
        repos.recently_updated
      end
      WillPaginate::Collection.create(page, Repository.per_page) do |pager|
        pager.replace(repos)
        pager.total_entries ||= search_results.total_entries
      end
    rescue ElastomerClient::Client::Error => boom
      Failbot.report boom
      Search::Results.empty
    end

    def search_phrase(type:, types:)
      type_query = if type.blank? || !type_filter_is_valid?(type: type, types: types)
        "fork:true" # include forks and archived by default
      elsif type == "private"
        "is:private fork:true" # private sources and forks
      elsif type == "source"
        "mirror:false fork:false archived:false" # exclude forks and archived
      elsif type == "fork"
        "fork:only archived:false" # only include forks
      elsif type == "mirror"
        "mirror:true fork:true archived:false" # mirror sources and forks
      elsif type == "archived"
        "archived:true fork:true" # archived sources and forks
      elsif type == "public"
        "is:public fork:true archived:false" # public sources and forks
      elsif type == "internal"
        "is:internal" # internal sources
      elsif type == "template"
        "template:true fork:true archived:false" # include forks and exclude archived
      end
      "#{phrase} #{type_query}".strip
    end

    def search_sort(order_by)
      case order_by
      when "name"
        %w(name asc)
      when "stargazers"
        %w(stars desc)
      else
        %w(updated desc)
      end
    end

    # Internal: Given a Repository scope, will return a modified scope that filters the
    # repositories according to the given type filter.
    def filter_repos_by_type(repos, type:, types:)
      # Disallow viewer filtering the user's repositories in a way we don't support.
      return repos unless type_filter_is_valid?(type: type, types: types)

      case type
      when "public" then repos.public_scope
      when "private" then repos.private_not_internal_scope
      when "internal" then repos.internal_scope
      when "source" then repos.not_archived_scope.where(parent_id: nil)
      when "fork" then repos.not_archived_scope.forks
      when "mirror" then repos.not_archived_scope.joins(:mirror)
      when "archived" then repos.archived_scope
      when "private-fork" then repos.private_scope.forks
      when "template" then repos.not_archived_scope.templates
      else repos
      end
    end
  end
end
