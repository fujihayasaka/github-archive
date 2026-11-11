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
      # DECIMAL(precision, scale) for filtering issue field number values.
      # Precision of 16 = 10 integer digits (max for 32-bit signed integer range) + 6 fractional digits.
      # Scale of 6 matches the fractional digit count used by the number-field search encoding.
      ISSUE_FIELD_NUMBER_FILTER_DECIMAL_PRECISION = 16
      ISSUE_FIELD_NUMBER_FILTER_DECIMAL_SCALE = 6

      # Maximum number of issue field value filters accepted per query.
      # Each filter adds a SQL JOIN; this guards against amplified DB
      # work from oversized or repeated filter lists.
      MAX_ISSUE_FIELD_VALUE_FILTERS = 20

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
          repo_ids = scope.unscope(:order).select(:repository_id).distinct.pluck(:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
        repo_ids = scope.where(pull_request_id: nil).distinct.pluck(:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

      def scope_for_issue_field_values(scope, issue_field_value_filters, repository: nil)
        issue_field_value_filters = issue_field_value_filters.uniq { |filter| filter.to_h }

        if issue_field_value_filters.size > MAX_ISSUE_FIELD_VALUE_FILTERS
          raise Platform::Errors::Unprocessable,
                "issueFieldValues must contain no more than #{MAX_ISSUE_FIELD_VALUE_FILTERS} filters."
        end

        issue_field_value_filters.each_with_index do |filter, index|
          table_alias = "issue_field_values_filter_#{index}"
          repository_id_column = issue_field_value_column_sql(table_alias, :repository_id)
          issue_id_column = issue_field_value_column_sql(table_alias, :issue_id)
          issue_field_id_column = issue_field_value_column_sql(table_alias, :issue_field_id)
          data_type_column = issue_field_value_column_sql(table_alias, :data_type)
          join_table = issue_field_value_table_sql(table_alias)
          field_id = resolve_field_id(filter, repository)
          data_type, value_sql, values = issue_field_value_filter_condition(filter, table_alias, field_id: field_id)

          return scope.none if field_id.nil? || data_type.nil? || value_sql.nil?

          join_sql = Issue.send(:sanitize_sql_array, [
            <<~SQL.squish,
              INNER JOIN issue_field_values #{join_table}
                ON #{repository_id_column} = issues.repository_id
               AND #{issue_id_column} = issues.id
               AND #{issue_field_id_column} = ?
               AND #{data_type_column} = ?
               AND #{value_sql}
            SQL
            field_id,
            data_type,
            *Array(values),
          ])

          scope = scope.joins(join_sql)
        end

        issue_field_value_filters.any? ? scope.distinct : scope
      end

      def issue_field_value_filter_condition(filter, table_alias, field_id: nil)
        text_value = filter_value(filter, :text_value)
        date_value = filter_value(filter, :date_value)
        number_value = filter_value(filter, :number_value)
        single_select_option_id = filter_value(filter, :single_select_option_id)
        single_select_option_value = filter_value(filter, :single_select_option_value)
        multi_select_option_ids = filter_value(filter, :multi_select_option_ids)
        multi_select_option_values = filter_value(filter, :multi_select_option_values)
        json_value_sql = "JSON_UNQUOTE(#{issue_field_value_column_sql(table_alias, :value)})"
        json_column_sql = issue_field_value_column_sql(table_alias, :value)

        # Returned whenever a filter can't be resolved to a usable condition. Defined once so the
        # shape of the "no match" tuple only needs to change in a single place.
        no_match = [nil, nil, nil]

        # Validate that at most one value argument is provided.
        provided_values = {
          text_value: text_value.present?,
          date_value: date_value.present?,
          number_value: !number_value.nil?,
          single_select_option_id: single_select_option_id.present?,
          single_select_option_value: single_select_option_value.present?,
          multi_select_option_ids: multi_select_option_ids.present?,
          multi_select_option_values: multi_select_option_values.present?,
        }
        if provided_values.values.count(true) > 1
          provided_keys = provided_values.select { |_, present| present }.keys.join(", ")
          raise Platform::Errors::Unprocessable,
                "Exactly one value argument must be provided for issue field value filters, but multiple were set: #{provided_keys}."
        end

        if text_value.present?
          [IssueField::DATA_TYPES[:text], "#{json_value_sql} = ?", text_value]
        elsif date_value.present?
          # Date issue field values can be stored either as a plain "YYYY-MM-DD" string
          # or as a full ISO 8601 datetime string comparison ignores any time component
          # and matches regardless of how the value was written.
          parsed_date = begin
            Date.iso8601(date_value)
          rescue ArgumentError, TypeError
            nil
          end
          return no_match if parsed_date.nil?

          date_cast_sql = "CAST(#{json_value_sql} AS DATE)"
          [IssueField::DATA_TYPES[:date], "#{date_cast_sql} = ?", parsed_date]
        elsif !number_value.nil?
          numeric_value = BigDecimal(number_value.to_s, exception: false)
          return no_match if numeric_value.nil?
          # Normalize to the same scale as the SQL DECIMAL cast so equality comparisons are consistent.
          numeric_value = numeric_value.round(ISSUE_FIELD_NUMBER_FILTER_DECIMAL_SCALE)
          number_cast_sql = "CAST(#{json_value_sql} AS DECIMAL(#{ISSUE_FIELD_NUMBER_FILTER_DECIMAL_PRECISION}, #{ISSUE_FIELD_NUMBER_FILTER_DECIMAL_SCALE}))"

          # Issue field numbers are currently validated to the 32-bit signed integer range, and the
          # adjacent number-field search encoding canonicalizes values to 6 fractional digits.
          [IssueField::DATA_TYPES[:number], "#{number_cast_sql} = ?", numeric_value]
        elsif single_select_option_id.present?
          option_id = decode_global_id(
            single_select_option_id,
            allowed_types: "IssueFieldSingleSelectOption",
          )
          return no_match if option_id.nil?

          [IssueField::DATA_TYPES[:single_select], "#{json_value_sql} = ?", option_id.to_s]
        elsif single_select_option_value.present?
          return no_match if field_id.nil?

          option = IssueFieldOption.find_by(issue_field_id: field_id, name: single_select_option_value)
          return no_match if option.nil?

          [IssueField::DATA_TYPES[:single_select], "#{json_value_sql} = ?", option.id.to_s]
        elsif multi_select_option_ids.present?
          return no_match if multi_select_field_search_owner_id(field_id).nil?

          requested_option_ids = Array(multi_select_option_ids).uniq
          decoded_option_ids = requested_option_ids.map do |option_id|
            decode_global_id(option_id, allowed_types: "IssueFieldSingleSelectOption")
          end
          return no_match if decoded_option_ids.any?(&:nil?)

          option_ids = decoded_option_ids.compact
          option_ids = option_ids.uniq
          return no_match if option_ids.empty?

          [IssueField::DATA_TYPES[:multi_select], multi_select_json_contains_sql(json_column_sql, option_ids.size), option_ids]
        elsif multi_select_option_values.present?
          return no_match if field_id.nil?
          owner_id = multi_select_field_search_owner_id(field_id)
          return no_match if owner_id.nil?

          option_names = Array(multi_select_option_values).uniq
          option_ids = IssueFieldOption.where(
            owner_id: owner_id,
            issue_field_id: field_id,
            name: option_names,
          ).pluck(:id)
          return no_match if option_ids.empty? || option_ids.size != option_names.size

          [IssueField::DATA_TYPES[:multi_select], multi_select_json_contains_sql(json_column_sql, option_ids.size), option_ids]
        else
          no_match
        end
      end

      def multi_select_json_contains_sql(json_column_sql, option_count)
        "(#{Array.new(option_count, "JSON_CONTAINS(#{json_column_sql}, ?)").join(" AND ")})"
      end

      def multi_select_field_search_owner_id(field_id)
        return nil if field_id.nil?

        field = IssueField.select(:owner_id).find_by(id: field_id)
        owner = Organization.find_by(id: field&.owner_id)
        return nil if owner.nil? || !IssueFieldsFeature.multi_select_enabled?(owner)

        owner.id
      end

      def quote_table_alias_sql(table_alias)
        Issue.connection.quote_table_name(table_alias)
      end

      def resolve_field_id(filter, repository)
        filter_field_id = filter_value(filter, :field_id)
        field_name = filter_value(filter, :field_name)

        if filter_field_id.present? && field_name.present?
          raise Platform::Errors::Unprocessable,
                "Cannot specify both `fieldId` and `fieldName`. Please provide exactly one."
        end

        if filter_field_id.present?
          decode_global_id(filter_field_id)
        elsif field_name.present?
          return nil if repository.nil?

          field = IssueField.find_by(name: field_name, owner: repository.owner)
          field&.id
        end
      end

      def issue_field_value_table_sql(table_alias)
        quote_table_alias_sql(table_alias)
      end

      def issue_field_value_column_sql(table_alias, column_name)
        quoted_table_alias = quote_table_alias_sql(table_alias)
        quoted_column_name = Issue.connection.quote_column_name(column_name)
        "#{quoted_table_alias}.#{quoted_column_name}"
      end

      def filter_value(filter, key)
        filter[key] || filter[key.to_s]
      end

      def decode_global_id(global_id, allowed_types: nil)
        type_name, database_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)

        if allowed_types
          allowed = Array(allowed_types).map!(&:to_s)
          return nil unless allowed.include?(type_name.to_s)
        end

        Integer(database_id)
      rescue Platform::Errors::NotFound, ArgumentError, TypeError
        nil
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

          if arguments[:filter_by][:issue_field_values]
            scope = scope_for_issue_field_values(scope, arguments[:filter_by][:issue_field_values], repository: repository)
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
            repo_ids = scope.pluck(:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
              scope = scope.where("issue_types.id IS NULL OR issue_types.enabled = false")
            when Search::Filter::WILDCARD
              scope = scope
                .joins(:issue_type)
                .where(issue_types: { enabled: true })
            else
              scope = scope
                .joins(:issue_type)
                .where(issue_types: { enabled: true })
                .where("issue_types.name LIKE ?", ActiveRecord::Base.sanitize_sql_like(arguments[:filter_by][:type]))
              # this ensures the query uses the owner_id index on issue_types
              scope = scope.where(issue_types: { owner_id: repository.owner_id })
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
