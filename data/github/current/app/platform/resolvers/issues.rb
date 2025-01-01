# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Issues < Resolvers::Base
      include Scientist

      argument :order_by, Inputs::IssueOrder, "Ordering options for issues returned from the connection.", required: false
      argument :labels, [String], "A list of label names to filter the pull requests by.", required: false
      argument :states,  [Enums::IssueState], "A list of states to filter the issues by.", required: false
      argument :filter_by, Inputs::IssueFilters, "Filtering options for issues returned from the connection.", required: false

      type Connections.define(Objects::Issue), null: false

      SORT_FIELD_MAPPINGS = {
        "created_at" => "created",
        "updated_at" => "updated",
        "comments"   => "comments",
      }.freeze

      def filter_components(arguments)
        components = []
        components << [:is, "issue"]

        case object
        when User
          components << [:author, object]
        when Repository
          components << [:repo, object.name_with_owner]
        when Label
          components << [:label, object.name]
        end

        if arguments[:filter_by]
          if labels = arguments[:filter_by][:labels]
            components << [:label, labels]
          end
        elsif arguments[:labels]
          components << [:label, arguments[:labels]]
        end

        # states is optional and can be ["open", "closed"] or ["closed"] or ["open"]
        # we only set the state if either open or closed is supplied and search
        # across all issues otherwise
        if arguments[:states] && arguments[:states].size == 1
          components << [:is, arguments[:states][0]]
        end

        if order_by = arguments[:order_by]
          field = SORT_FIELD_MAPPINGS[order_by[:field].downcase]
          component = [field, order_by[:direction].downcase].join("-")
          components << [:sort, component]
        else
          components << [:sort, "created-ASC"]
        end

        components
      end

      def self.label_search?(arguments)
        # The value of the :labels key could be nil so we can't use .fetch
        has_labels = (arguments[:labels] || []).any?
        filter_keys = arguments.fetch(:filter_by, {}).keys
        only_filter_by_labels = filter_keys.uniq == [:labels]

        has_labels || only_filter_by_labels
      end

      FILTER_REPO_ID_COUNT_LIMIT = 5000

      def resolve(**arguments)
        case object
        when User
          scope = object.issues
          scope = context[:permission].filter_permissible_repository_resources(object, scope, resource: "issues")

          scope = apply_args(scope, arguments)

          # The state condition here helps MySQL pick the correct index.
          scope = scope.without_pull_requests.filter_spam_for(context[:viewer]).where(state: ::Issue::State::States)
          repo_ids = scope.unscope(:order).select(:repository_id).distinct.pluck(:repository_id)
          if repo_ids.size > FILTER_REPO_ID_COUNT_LIMIT
            Failbot.report(
               StandardError.new("repository id count exceeds limit"),
               repo_id_count: repo_ids.size,
               repo_id_limit: FILTER_REPO_ID_COUNT_LIMIT
            )
            repo_ids = repo_ids.first(FILTER_REPO_ID_COUNT_LIMIT)
          end
          filtered_repo_ids = Repository.where(id: repo_ids, user_hidden: false).pluck(:id)
          scope.where(repository_id: filtered_repo_ids)
        when Label
          object.async_repository.then do |repo|
            next Issue.none if repo.spammy?

            scope = repo.issues.labeled(object)
            if (arguments[:filter_by] && arguments[:filter_by][:labels]) || arguments[:labels]
              # TODO: deprecate in favor of filter_by namespacing https://github.com/github/github/pull/95997#discussion_r210916544
              name = (arguments[:filter_by] && arguments[:filter_by][:labels]) ? arguments[:filter_by][:labels] : arguments[:labels]

              # This is slightly odd, but I promise it makes sense. If we hit this case, it means we have a query like:
              # query {
              #   repository(owner: "dotnet", name: "coreclr") {
              #     label(name: "area-CodeGen") {
              #       issues(labels: ["tenet-performance", "optimization"], first: 10) {
              #       ...
              # Which is functionally looking for issues that are _inheriting_ from a label, as well as filtering by
              #  _additional_ (and potentially different) Labels inside of that one Repository.
              # If you imagine the parent Label as 'Help Wanted' and the arguments to the connection as the labels
              # 'Front End' and 'Web', we're looking for Labels matching: 'Help Wanted' AND ('Front End' OR 'Web')
              #
              # In order to do this, we utilize the scope set above which is ALL issues tagged 'Help Wanted'
              # and add in a sub-select for all of the issues that are 'Front End' OR 'Web'
              #
              # In effect, this is an INTERSECT query between 'Help Wanted' and ('Front End' OR 'Web'), but done
              # without INTERSECT because it's not a MySQL feature.
              child_issues = repo.issues.joins(:labels).merge(Label.with_name(name)).select("issues.id")
              scope = scope.where("issues.id IN (#{child_issues.to_sql})")
            end

            unless context[:permission].can_list_issues?(object, repo)
              next Issue.none unless repo.public?
            end

            # Note that we skip the :labels argument here, because we've already applied it above
            # If there was no labels argument, it doesn't really matter that we're skipping it
            apply_args(scope, arguments, except: [:labels], repository: repo).without_pull_requests.filter_spam_for(context[:viewer])
          end
        when Repository
          repository  = object
          scope       = T.let(Issue.where(repository_id: repository.id), ActiveRecord::Relation)

          repository.async_owner.then do |owner|
            unless context[:permission].can_list_issues?(owner, repository)
              scope = repository.public? ? scope : Issue.none
            end

            scope_for_repo(scope, arguments, repository: repository)
          end
        when Milestone
          object.async_repository.then do |repo|
            next Issue.none if repo.spammy?
            unless context[:permission].can_list_issues?(object, repo)
              next Issue.none unless repo.public?
            end
            scope = object
                      .issues
                      .without_pull_requests
                      .joins("LEFT JOIN `issue_priorities` ON `issue_priorities`.`issue_id` = `issues`.`id`")
                      .order("issue_priorities.priority DESC, issues.id ASC")

            scope = apply_args(scope, arguments, repository: repo)

            scope = scope.filter_spam_for(context[:viewer])
            if arguments[:order_by].blank?
              # Use a custom connection wrapper here since it's sorted by a join table, `issue_priorities`
              scope = scope.select("issues.*, issue_priorities.priority")
              ConnectionWrappers::MilestoneMembersByPriority.new(scope)
            else
              scope
            end
          end
        when ::IssueType
          Helpers::NodeIdentification.async_typed_object_from_id(
            [Objects::Repository],
            arguments[:repository_id],
            context
          ).then do |repository|
            repository.async_owner.then do |owner|
              unless repository.public? || context[:permission].can_list_issues?(owner, repository)
                next Issue.none
              end

              scope = object.issues.where(repository: repository)

              apply_args(scope, arguments, repository: repository).filter_spam_for(context[:viewer])
            end
          end
        else
          raise Platform::Errors::Internal, "Unexpected issues owner #{object.class}"
        end
      end

      def scope_for_repo(scope, arguments, repository: nil)
        if !arguments[:order_by]
          arguments[:order_by] = { field: "created_at", direction: "ASC" }
        end

        viewer = context[:viewer]
        repo_ids = scope.where(pull_request_id: nil).distinct.pluck(:repository_id)
        filtered_repo_ids =
          Repository.with_issues_enabled.filter_spam_for(viewer).where(id: repo_ids).select(:id).distinct.pluck(:id)

        scope = scope.where(repository_id: filtered_repo_ids).or(scope.where.not(pull_request_id: nil))
        scope = apply_args(scope, arguments, repository: repository)
        scope.without_pull_requests.filter_spam_for(viewer)
      end

      def scope_for_labels(scope, repository, labels)
        scope = if repository
          scope.joins(:labels).merge(repository.labels.with_name(labels))
        else
          scope.joins(:labels).merge(Label.with_name(labels))
        end
        labels.size > 1 ? scope.distinct : scope
      end

      def apply_args(scope, arguments, except: [], repository: nil)
        if arguments[:order_by]
          scope = scope.reorder(ActiveRecord::Base::sanitize_sql_for_order(["issues.#{arguments[:order_by][:field]} #{arguments[:order_by][:direction]}"]))
        end

        # TODO: deprecate in favor of filter_by namespacing https://github.com/github/github/pull/95997#discussion_r210916544
        if arguments[:states]
          scope = scope.where(state: arguments[:states])
        end

        if arguments[:labels] && !except.include?(:labels)
          scope = scope_for_labels(scope, repository, arguments[:labels])
        end

        if arguments[:filter_by]
          if arguments[:filter_by][:states]
            scope = scope.where(state: arguments[:filter_by][:states])
          end

          if arguments[:filter_by][:labels] && !except.include?(:labels)
            scope = scope_for_labels(scope, repository, arguments[:filter_by][:labels])
          end

          if arguments[:filter_by][:since]
            scope = scope.since(arguments[:filter_by][:since])
          end

          if arguments[:filter_by].key?(:assignee)
            case arguments[:filter_by][:assignee]
            when Search::Filter::WILDCARD
              scope = scope.assigned
            when nil
              scope = scope.unassigned
            else
              scope = scope.assigned_to(arguments[:filter_by][:assignee])
            end
          end

          if arguments[:filter_by][:mentioned]
            user = User.find_by_login(arguments[:filter_by][:mentioned])
            return scope.none if user.nil?

            scope = scope.mentioning(user)
          end

          if arguments[:filter_by][:created_by]
            scope = scope.created_by(arguments[:filter_by][:created_by])
          end

          # TODO decide if this should be deprecated since it uses the milestone's
          # database ID and not it's number scoped by repository?
          if arguments[:filter_by].key?(:milestone)
            case arguments[:filter_by][:milestone]
            when Search::Filter::WILDCARD
              scope = scope.with_any_milestone
            when nil
              scope = scope.with_no_milestone
            else
              scope = scope.for_milestone(arguments[:filter_by][:milestone])
            end
          end

          if arguments[:filter_by].key?(:milestone_number)
            case arguments[:filter_by][:milestone_number]
            when Search::Filter::WILDCARD
              scope = scope.with_any_milestone
            when nil
              scope = scope.with_no_milestone
            else
              scope = scope.for_milestone_number(arguments[:filter_by][:milestone_number])
            end
          end

          if arguments[:filter_by][:viewer_subscribed]
            repo_ids = scope.pluck(:repository_id)
            lists = repo_ids.map { |id| ::Newsies::List.new(Repository.name, id) }
            threads_response = GitHub.newsies.subscribed_threads(context[:viewer], lists, "Issue")

            if threads_response.failed?
              raise Platform::Errors::ServiceUnavailable, "Notifications are not available"
            end

            scope = scope.from_ids(threads_response.map(&:thread_id))
          end

          # we currently only support filtering by type on repository scoped queries
          if arguments[:filter_by].key?(:type) && repository
            case arguments[:filter_by][:type]
            when nil
              scope = scope.left_joins(:issue_type)
              scope = if repository.public?
                # private issue types don't appear in public repositories, so if an issue is typed with a private type
                # in a public repo, then we should match this nil case
                scope.where("issue_types.id IS NULL OR issue_types.enabled = false OR issue_types.private = true")
              else
                scope.where("issue_types.id IS NULL OR issue_types.enabled = false")
              end
            when Search::Filter::WILDCARD
              scope = scope
                .joins(:issue_type)
                .where(issue_types: { enabled: true })
              scope = scope.where(issue_types: { private: false }) if repository.public?
            else
              scope = scope
                .joins(:issue_type)
                .where(issue_types: { enabled: true })
                .where("issue_types.name LIKE ?", ActiveRecord::Base.sanitize_sql_like(arguments[:filter_by][:type]))
              # this ensures the query uses the owner_id index on issue_types
              scope = scope.where(issue_types: { owner_id: repository.owner_id })
              # we can remove this once we remove private issue types, but for now, they can only be used in private
              # repositories, so we need to filter them out of public repos
              scope = scope.where(issue_types: { private: false }) if repository.public?
            end
          end
        end

        scope

      rescue Issue::AssigneeInvalid => e
        raise Platform::Errors::Unprocessable, "Could not find an assignee with the login '#{e.assignee}'."
      end
    end
  end
end
