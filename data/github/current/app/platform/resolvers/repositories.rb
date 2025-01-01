# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Repositories < Resolvers::Base
      include Scientist
      include Search::RepositoryQueryFilters
      include ::Repositories::Domain::Provider
      include Platform::Resolvers::CurrentLookahead

      argument :privacy, Enums::RepositoryPrivacy,
        "If non-null, filters repositories according to privacy. Internal repositories are considered private; consider using the visibility argument if only internal repositories are needed. Cannot be combined with the visibility argument.",
        required: false

      argument :visibility, Enums::RepositoryVisibility,
        "If non-null, filters repositories according to visibility. Cannot be combined with the privacy argument.",
        required: false

      argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection", required: false

      argument :affiliations, [Enums::RepositoryAffiliation, null: true],
        required: false,
        description: "Array of viewer's affiliation options for repositories returned from the connection. For example, OWNER will include only repositories that the current viewer owns."

      argument :owner_affiliations, [Enums::RepositoryAffiliation, null: true],
        required: false,
        description: "Array of owner's affiliation options for repositories returned from the connection. For example, OWNER will include only repositories that the organization or user being viewed owns.",
        default_value: [:owned, :direct]

      argument :is_locked, Boolean,
        required: false,
        description: "If non-null, filters repositories according to whether they have been locked"

      argument :language, String,
        "An optional, case-insensitive programming language to use to filter the repositories (e.g. 'Ruby')",
        required_capabilities: [:mobile_only_schema_mask], required: false

      argument :type, Enums::RepositoryType,
        "An optional type to use to filter the repositories.",
        required_capabilities: [:mobile_only_schema_mask], required: false

      argument :has_issues_enabled, Boolean,
      required: false,
      description: "If non-null, filters repositories according to whether they have issues enabled"

      argument :query, String, "An optional filter to search the repositories.",
        required_capabilities: [:mobile_only_schema_mask], required: false

      type Connections::Repository, null: false

      def resolve(
        privacy: nil,
        visibility: nil,
        order_by: nil,
        affiliations: nil,
        owner_affiliations: nil,
        is_archived: nil,
        is_fork: nil,
        is_locked: nil,
        sponsorable_only: false,
        language: nil,
        type: nil,
        query: nil,
        has_issues_enabled: nil,
        override_query_phrase: false
      )
        if privacy && visibility
          raise Platform::Errors::ArgumentError, "Privacy and visibility cannot both be specified"
        end

        if object.try(:private_profile_for?, context[:viewer])
          order_by = (order_by&.to_h || { direction: "ASC" }).merge(field: "name")
        end

        if query.present? || language.present?
          search_repositories(query: query, override_query_phrase: override_query_phrase, language: language, order_by: order_by, type: type)
        else
          list_repositories(
            privacy: privacy,
            visibility: visibility,
            order_by: order_by,
            affiliations: affiliations,
            owner_affiliations: owner_affiliations,
            is_archived: is_archived,
            is_locked: is_locked,
            is_fork: is_fork,
            type: type,
            has_issues_enabled: has_issues_enabled,
            sponsorable_only: sponsorable_only
          )
        end
      end

      def list_repositories(
        privacy: nil,
        visibility: nil,
        order_by: nil,
        affiliations: nil,
        owner_affiliations:,
        is_archived: nil,
        is_locked: nil,
        is_fork: nil,
        language: nil,
        type: nil,
        has_issues_enabled: nil,
        sponsorable_only: false,
        query: nil
      )
        kwargs = {
          affiliations: affiliations,
          default_affiliations: default_affiliations,
          has_issues_enabled: has_issues_enabled,
          is_archived: is_archived,
          is_fork: is_fork,
          is_locked: is_locked,
          order_by: order_by,
          privacy: privacy,
          sponsorable_only: sponsorable_only,
          type: type,
          visibility: visibility,
        }

        if object.is_a?(Organization)
          organization_repos(**kwargs)
        else
          kwargs = kwargs.merge({
            owner_affiliations: owner_affiliations,
            check_large_scope: true,
            remove_duplicate_in_clause: true
          })

          finder = T.cast(::Repositories::Public.finder_for(
            owner: object,
            viewer: context[:viewer],
            unauthorized_viewer_organization_ids: context[:unauthorized_organization_ids],
            permission: context[:permission],
            repo_type: repository_finder_type,
          ), RepositoriesFinder)
          unpaginated_repos = finder.filter(**kwargs)

          unless unpaginated_repos.is_a?(RepositoriesFinder::LargeScope)
            return unpaginated_repos
          end

          kwargs = kwargs.merge({ cursor: cursor })
          paginated_repos = finder.filter(**kwargs)
          if paginated_repos.count.present?
            Wrappers::RemoteProxyRelation.new(paginated_repos.scope, count: paginated_repos.count)
          else
            unpaginated_repos.scope
          end
        end
      end

      def domain_actor
        context[:viewer]
      end

      private

      def organization_repos(**kwargs)
        sort = [kwargs[:order_by].respond_to?(:field) ? kwargs[:order_by].field : kwargs.dig(:order_by, :field)].compact
        direction = kwargs[:order_by].respond_to?(:direction) ? kwargs[:order_by].direction : kwargs.dig(:order_by, :direction)
        visibility = kwargs[:visibility] ? ::Repositories::RepositoryVisibility.deserialize(kwargs[:visibility].to_s) : nil
        privacy = kwargs[:privacy] ? ::Repositories::RepositoryVisibility.deserialize(kwargs[:privacy].to_s) : nil

        kwargs = {
          with_members: with_items?,
          with_total_count: with_total_count?,
          with_total_disk_usage: with_total_disk_usage?,
          with_page_info: with_page_info?,
          affiliations: kwargs[:affiliations]&.map { |affiliation| ::Repositories::RepositoryAffiliation.deserialize(affiliation) },
          default_affiliations: default_affiliations&.map { |affiliation| ::Repositories::RepositoryAffiliation.deserialize(affiliation) },
          direction: direction.present? ? GH::Pagination::Sort::Direction.deserialize(direction) : nil,
          finder_type: repository_finder_type,
          has_issues_enabled: kwargs[:has_issues_enabled],
          is_archived: kwargs[:is_archived],
          is_fork: kwargs[:is_fork],
          is_locked: kwargs[:is_locked],
          organization: object,
          pagination: GH::Pagination::Cursor.from_hash(context[:current_arguments]&.to_h),
          permission: ::Repositories::PlatformPermissionSwitch.new(context[:permission]),
          privacy:,
          sort: sort.present? ? ::Repositories::SortBy.deserialize(sort) : nil,
          sponsorable_only: kwargs[:sponsorable_only],
          type: kwargs[:type] ? ::Repositories::RepositoryType.deserialize(kwargs[:type]) : nil,
          unauthorized_organization_ids: context[:unauthorized_organization_ids],
          user: context[:viewer],
          visibility:,
        }
        begin
          repositories_domain.by_org_member(::Repositories::ByOrgMemberArgs.new(**kwargs.compact))
        rescue ::Repositories::Domain::BadActorGate::Error::UnprocessableEntity => e
          raise Platform::Errors::Unprocessable, e.message
        end
      end

      def cursor
        return @cursor if defined?(@cursor)

        cursor = {}

        begin
          current_arguments = context[:current_arguments] || {}
          if before = current_arguments[:before]
            cursor[:before] = ConnectionWrappers::CursorGenerator.resolve_cursor(before)
          end

          if after = current_arguments[:after]
            cursor[:after] = ConnectionWrappers::CursorGenerator.resolve_cursor(after)
          end

          if first = current_arguments[:first]
            cursor[:first] = first
          end

          if last = current_arguments[:last]
            cursor[:last] = last
          end

          if cursor.keys.size == 0
            cursor = nil
          end
        rescue Platform::Errors::Cursor
          cursor = nil
        end

        @cursor = cursor
      end

      # Required for compatibility with subclasses of this resolver
      def repository_finder_type
        RepositoriesFinder::REPO_TYPE_DEFAULT
      end

      # Required for compatibility with subclasses of this resolver
      def default_affiliations
        [:owned, :direct]
      end

      def search_repositories(query:, override_query_phrase:, language:, order_by:, type:)
        phrase = override_query_phrase ? query : search_phrase(query, type, object.login)
        Search::Queries::RepoQuery.new(phrase: phrase,
                                       user_session: context[:user_session],
                                       current_user: context[:viewer],
                                       cap_filter: context[:cap_filter],
                                       source_fields: false,
                                       star_search: false,
                                       include_forks: true,
                                       star_user: object,
                                       language: language,
                                       sort: search_sort(order_by))
      end

      def with_total_disk_usage?
        with_safe_access_to_current_lookahead do |current_lookahead|
          current_lookahead.selects?("totalDiskUsage")
        end
      end

      protected

      # Apply the specified ordering to the overall list, in case the repositories were fetched
      # in batches with only each batch being ordered in SQL
      def sort_repo_list(repos, order_by)
        if order_by
          # This column has been marked for rename. We need to refer to the new name here as this
          # accesses the model's attribute, not the database column. This can go when the rename
          # is complete.
          field = order_by[:field] == "watcher_count" ? "stargazer_count" : order_by[:field]
          repos = repos.sort_by { |repo| repo[field].to_s }
          repos = repos.reverse if order_by[:direction] == "DESC"
        end

        repos
      end
    end
  end
end
