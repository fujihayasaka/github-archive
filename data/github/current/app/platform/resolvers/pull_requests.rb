# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PullRequests < Resolvers::Base
      include Scientist

      argument :states, [Enums::PullRequestState], "A list of states to filter the pull requests by.", required: false

      argument :labels, [String], "A list of label names to filter the pull requests by.", required: false

      argument :head_ref_name, String, "The head ref name to filter the pull requests by.", required: false

      argument :base_ref_name, String, "The base ref name to filter the pull requests by.", required: false

      argument :order_by, Inputs::IssueOrder, "Ordering options for pull requests returned from the connection.", required: false

      def self.filter_by_argument
        argument :filter_by,
          Inputs::PullRequestFilters,
          "Filtering options for pull requests returned by the connection. Specifying this argument will nullify the effects of the other filtering arguments on this connection.",
          required: false,
          feature_flag: :gh_cli
      end
      # This is a hack to work around a cyclical loading issue.
      # It should be fixed upstream somehow, so ask in #graphql
      # before you copy this.
      null(false)
      def self.type_expr
        Connections.define(Objects::PullRequest)
      end

      def resolve(**arguments)
        if arguments[:filter_by]
          # This codepath is currently not in use according to https://github.com/github/github/pull/354629
          async_unified_resolve(arguments)
        else
          legacy_resolve(arguments)
        end
      end

      private

      def legacy_resolve(arguments)
        Promise.resolve(fetch_pull_requests(object, arguments, context)).then do |relation|
          relation = filter_pull_requests(relation, arguments, context[:viewer])
          relation = order_pull_requests(relation, arguments[:order_by])
          wrap_connection(relation, arguments)
        end
      end

      # `MilestonePullRequests` needs this to do a custom wrapper
      def wrap_connection(relation, _arguments)
        relation
      end

      def async_unified_resolve(arguments)
        async_can_list_pull_requests?.then do |can_list|
          next [] unless can_list
          components = sort_components(arguments[:order_by]) +
                       filter_components(arguments[:filter_by])

          async_query_object(components, sort_arguments = arguments[:order_by])
        end
      end

      def async_can_list_pull_requests?
        async_repository.then do |repo|
          context[:permission].async_can_list_pull_requests?(repo).then do |can_list_pull_requests|
            if repo
              can_list_pull_requests
            else
              raise Errors::Internal, "Please define #async_can_list_pull_requests? in subclasses of Resolvers::PullRequests or return a repository for async_repository"
            end
          end
        end
      end

      def async_query_object(components, sort_arguments)
        async_repository.then do |repo|
          if repo && ::Issue::MysqlSearch.supported?(components, context[:viewer])
            issues_scope = ::Issue::MysqlSearch.query_scope(repo: repo, query: components, current_user: context[:viewer], show_spam_to_staff: true)
            prs_scope = ::PullRequest.merge(issues_scope).from("`pull_requests` INNER JOIN `issues` IGNORE INDEX FOR ORDER BY (PRIMARY) ON `issues`.`pull_request_id` = `pull_requests`.`id`")

            if sort_arguments.present? && sort_arguments[:field].present?
              sort_field = safe_sort_field(sort_arguments[:field])
            else
              sort_field = nil
            end

            # Vitess needs the sort column to be selected:
            if sort_field
              prs_scope = prs_scope.select("pull_requests.*, issues.id as issue_id, issues.#{sort_field} as sort_field") # provided sort field
            else
              prs_scope = prs_scope.select("pull_requests.*, issues.id as issue_id, issues.created_at as issue_created_at") # default sort field
            end

            prs_scope
          else
            Helpers::IssuesQuery.new(components, viewer: context[:viewer], repository: repo)
          end
        end
      end

      def filter_components(filter)
        components = query_components
        components << [:is, "pr"]

        return components unless filter

        components << [:is, filter[:state]] if filter[:state]
        filter[:labels].each { |label| components << [:label, label] } if filter[:labels]
        components << [:"reviewed-by", filter[:reviewed_by]] if filter[:reviewed_by]
        components << [:"review-requested", filter[:review_requested]] if filter[:review_requested]
        components << [:review, filter[:review_state]] if filter[:review_state]
        components << [:assignee, filter[:assignee]] if filter[:assignee]
        components << [:author, filter[:author]] if filter[:author]
        components << [:milestone, filter[:milestone]] if filter[:milestone]
        components << [:mentions, filter[:mentions]] if filter[:mentions]
        components << [:base, filter[:base_ref_name]] if filter[:base_ref_name]

        components
      end

      SORT_FIELD_MAPPINGS = {
        "created_at" => "created",
        "updated_at" => "updated",
        "comments"   => "comments",
      }.freeze

      def sort_components(order_by)
        return [[:sort, "created-asc"]] if order_by.nil?

        field = SORT_FIELD_MAPPINGS[order_by[:field].downcase]
        component = [field, order_by[:direction].downcase].join("-")
        [[:sort, component]]
      end

      # This method avoids a CodeQL SQL injection error by:
      # - loading the possible sort fields from the IssueOrderField;
      # - finding the value that matches the sort value;
      # - returning the value from the enum so it's not a user-supplied value,
      #   or nil if it doesn't exist.
      def safe_sort_field(sort_field)
        Platform::Enums::IssueOrderField.values.each_value.find { |e| e.value == sort_field }&.value
      end

      # Please define in subclasses. Returns an ActiveRecord::Relation or a Promise<ActiveRecord::Relation>
      def fetch_pull_requests(object, _, _)
        raise Errors::Internal, "Please define #fetch_pull_requests in subclasses of Resolvers::PullRequests"
      end

      # Public: the array of parsed query components (without filters) required as a base to establish this connection
      def query_components
        raise Errors::Internal, "Please define #build_query_builder in subclasses of Resolvers::PullRequests"
      end

      # Public: Returns the repository when the query is scoped to a single repository
      def async_repository
        raise Errors::Internal, "Please define #repository in subclasses of Resolvers::PullRequests"
      end

      # Public: Only return pull requests from repositories the viewer can see
      def filter_scope_by_visibility(scope, repository, can_list_pull_requests)
        if can_list_pull_requests || repository.public
          scope
        else
          PullRequest.none
        end
      end

      def filter_pull_requests(relation, arguments, viewer)
        if !viewer&.site_admin?
          pull_repo_ids = relation.unscope(:order).group(:repository_id).pluck(:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          # Hide spammy and DMCA takedown repos from non-site-admins

          relation = relation.unscope(where: :repository_id) if (viewer || User.ghost).feature_enabled?(:pull_requests_resolver_remove_double_repository_filter)
          relation = relation.where(repository_id: ::Repositories.domain.filter_spam_from_repo_ids(current_user: viewer, repo_ids: pull_repo_ids, exclude_disabled_repos: true))
        end

        relation = relation.filter_spam_for(viewer)

        if arguments[:states]
          if GitHub.flipper[:new_pull_request_state_filter].enabled?
            ConditionalPullRequestStateFilterJob.perform_later(ids: relation.limit(100).pluck(:id), states: arguments[:states]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end

          relation = ::Platform::Helpers::PullRequestStateFilter.filter(relation, arguments[:states])
        end

        if arguments[:labels]
          relation = relation.labeled(arguments[:labels])
        end

        if arguments[:head_ref_name]
          relation = relation.where(head_ref: arguments[:head_ref_name])
        end

        if arguments[:base_ref_name]
          relation =
            if viewer&.feature_enabled?(:base_repository_index_pr_graphql_api_experiment)
              relation.where(base_ref: arguments[:base_ref_name]).where("pull_requests.repository_id = pull_requests.base_repository_id")
            else
              relation.where(base_ref: arguments[:base_ref_name])
            end
        end

        relation
      end

      def order_pull_requests(relation, order_by)
        return relation unless order_by

        if order_by[:field].start_with?("issue")
          relation = relation.joins(
            " INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_requests`.`id`",
          )
          field_name = "issues.#{order_by[:field]}"
          relation = relation.select("pull_requests.*, issues.id as issue_id, #{field_name} as sort_field").order("#{field_name} #{order_by[:direction]}")
        else
          relation = relation.order("pull_requests.#{order_by[:field]} #{order_by[:direction]}")
        end

        relation
      end
    end
  end
end
