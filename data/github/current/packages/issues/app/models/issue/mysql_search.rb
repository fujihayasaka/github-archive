# typed: true
# frozen_string_literal: true

require "scientist"

class Issue
  module MysqlSearch
    extend Scientist

    SUPPORTED_FIELDS = [
      :assignee, :author, :is, :label, :milestone, :sort, :type
    ]

    OPEN_COUNT = :open_count
    CLOSED_COUNT = :closed_count
    ISSUES = :issues

    # Public
    # Simple queries can go straight through MySql instead of using ElasticSearch.
    # We pass the current_user solely for checking feature flags.
    def self.supported?(query, current_user = nil)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      return false if has_any_labels?(query, current_user)

      query.all? do |component|
        if !component.is_a?(Array)
          # fulltext search
          false
        elsif component[0] == :no && %w(milestone assignee).include?(component[1])
          # no:milestone, no:assignee
          true
        elsif component[0] == :label && component[2]
          # -label:bug goes to es
          false
        elsif component[0] == :sort && component[1].start_with?("interactions-")
          # sort:interactions-desc, sort:interactions-asc goes to es
          false
        elsif current_user&.feature_flag_enabled_or_raise?(:es_comment_sorting) && component[0] == :sort && component[1].start_with?("comments-") # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          # sort:comments-desc, sort:comments-asc goes to ES because the pull request comment count is incorrect when sorting via mysql
          false
        elsif component[0] == :is && component[1] == "draft"
          # draft status is only indexed in es
          false
        elsif component[0] == :is && component[1] == "queued"
          # queued state is only indexed in es
          false
        elsif component.first == :reason
          # reason:* goes to es until we have state_reason covering indexes for the issues table
          false
        elsif component[0] == :type  && component[1] == "pr"
          # since type can filter for issue,pr, or issue_type, we should filter and send type:pr to mysql
          true
        elsif component[0] == :type  && component[1] == "issue"
          # since type can filter for issue,pr, or issue_type, we should filter and send type:issue to mysql
          true
        elsif component[0] == :type
          false
        else
          SUPPORTED_FIELDS.include?(component.first)
        end
      end
    end

    # Runs a search on the database given a `query`. (Internal method)
    #
    # Returns a Hash with the following values:
    #
    #   hash[:issues]       - The paginated issues results array.
    #   hash[:open_count]   - The number of open issues for this query.
    #   hash[:closed_count] - The total number of closed issues for this query.
    #
    # :force_pulls is deprecated, please use `:force_type` instead
    def self.search(repo:,
                              query:,
                              current_user: nil,
                              remote_ip: nil,
                              user_session: nil,
                              page: 1,
                              per_page: 25,
                              force_pulls: false,
                              force_type: nil,
                              show_spam_to_staff: false,
                              initial_scope: nil,
                              pulls_index_request: false,
                              tags: [],
                              **kargs)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      sort = get_sort(query)
      force_type = :pull_requests if force_pulls && force_type.nil?

      if repo_spammy_for?(repo, current_user, show_spam_to_staff)
        # Use a NullRelation, effectively hiding issues coming from a spammy repo.
        scope = (initial_scope || repo.issues).none
      else
        scope = partial_query_scope_candidate(
          repo: repo,
          current_user: current_user,
          initial_scope: initial_scope,
          query: query,
          force_type: force_type,
          show_spam_to_staff: show_spam_to_staff,
        )
      end

      # This uses the unsorted scope -- when counting we don't care about the sorting
      state_count = Issue::SearchMetrics.track("issue.search.state_count.time", tags: tags) do
        count_by_state(scope, repo, query, force_type, current_user)
      end
      open_count   = state_count[OPEN_COUNT]
      closed_count = state_count[CLOSED_COUNT]

      scope              = sort_scope(sort, scope)
      filter, scope      = state_scope(query, scope)
      pagination_options = { per_page: per_page, page: page }

      case filter
      when "open"
        pagination_options[:total_entries] = open_count.to_i
      when "closed"
        pagination_options[:total_entries] = closed_count.to_i
      when "all"
        pagination_options[:total_entries] = open_count.to_i + closed_count.to_i
      end

      if scope.null_relation?
        scope.paginate(pagination_options)
      else
        pagination_scope = scope.select(:id).paginate(pagination_options)

        scope = sort_scope(sort, Issue.where("`issues`.`id` IN (SELECT * FROM (?) subquery_for_limit)", pagination_scope))

        # Copy over pagination attributes
        scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
        scope = scope.per_page(per_page)
        scope.current_page = pagination_scope.current_page
        scope.total_entries = pagination_scope.total_entries
      end

      {
        OPEN_COUNT   => open_count,
        CLOSED_COUNT => closed_count,
        ISSUES       => scope
      }
    end

    def self.count_by_state(scope, repo, parsed_query, force_type, current_user)
      open_count = query_count_by_state(scope, state: "open")
      closed_count = query_count_by_state(scope, state: "closed")

      # The query is assumed to be parsed by now so safe to check for default status.
      if ::Search::Queries::IssueQuery.is_default_issues_index_query?(parsed_query)
        # This will get called prior to the other occurence of this method within Issues#Index
        # And therefore the cache value time saving will be actually in the other invocation.
        if force_type == :pull_requests
          repo.set_open_pull_request_count_for(current_user, open_count.value)
        else
          repo.set_open_issue_count_for(current_user, open_count.value)
        end
      end

      {
        OPEN_COUNT   => open_count.value, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        CLOSED_COUNT => closed_count.value # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      }
    end

    # Public
    def self.query_scope(repo:, current_user: nil, initial_scope: nil, query:, force_type: nil, show_spam_to_staff: false)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)

      if repo_spammy_for?(repo, current_user, show_spam_to_staff)
        # Use a NullRelation, effectively hiding issues coming from a spammy repo.
        scope = (initial_scope || repo.issues).none
      else
        scope = partial_query_scope(
          repo: repo,
          current_user: current_user,
          initial_scope: initial_scope,
          query: query,
          force_type: force_type,
          show_spam_to_staff: show_spam_to_staff
        )
      end

      sort = get_sort(query)
      scope = sort_scope(sort, scope)

      state_scope(query, scope).last
    end

    def self.partial_query_scope(repo:, current_user: nil, initial_scope: nil, query:, force_type: nil, show_spam_to_staff: false)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      scope = initial_scope || repo.issues

      scope = type_scope_with_has_pull_request(query, scope, repo, force_type: force_type)
      scope = merge_state_scope(query, scope)
      scope = author_scope(query, scope, current_user)
      scope = assignee_scope(query, scope, current_user)
      scope = label_scope(repo, query, scope, current_user)
      scope = reason_scope(query, scope)
      scope = mention_scope(repo, query, scope, current_user)
      scope = milestone_scope(repo, query, scope)
      scope = issue_type_scope(repo, query, scope, current_user, force_type)
      scope = no_scope(repo, query, scope, current_user, force_type)

      scope.filter_spam_for(current_user, show_spam_to_staff: show_spam_to_staff)
    end

    def self.partial_query_scope_candidate(repo:, current_user: nil, initial_scope: nil, query:, force_type: nil, show_spam_to_staff: false)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      scope = initial_scope || repo.issues

      scope = type_scope_with_has_pull_request(query, scope, repo, force_type: force_type)
      scope = merge_state_scope(query, scope)
      scope = author_scope(query, scope, current_user)
      scope = assignee_scope(query, scope, current_user)
      scope = label_scope_candidate(repo, query, scope, current_user)
      scope = reason_scope(query, scope)
      scope = mention_scope(repo, query, scope, current_user)
      scope = milestone_scope(repo, query, scope)
      scope = issue_type_scope(repo, query, scope, current_user, force_type)
      scope = no_scope(repo, query, scope, current_user, force_type)

      scope.filter_spam_for(current_user, show_spam_to_staff: show_spam_to_staff)
    end

    # Internal: Determine the number of issues in the given scope that have the
    # given state.
    #
    # scope - An ActiveRecord::Relation for a collection of Issues.
    # state - The String issue state ("open" or "closed") (default: "open").
    #
    # Returns a Integer.
    def self.query_count_by_state(scope, state: "open")
      # The scope may or may not include a GROUP BY clause. (If the scope
      # filters by label and force_deduplicate is true, then it will include a GROUP BY clause.)
      #
      # If the scope is GROUPed, a regular COUNT will contain per-group counts
      # on each row returned, which would need to be summed.
      #
      # Instead of doing this we SELECT 1 for the search scope and run that as a subquery,
      # COUNTing the number of rows in that subquery.
      #
      # The query cost of the regular count("issues.id") and a nested query count are equivalent
      #
      # HOWEVER
      # We are not currently enforcing a unique constraint on [repository_id, name] on the Labels table,
      # so we need to handle the scenario where duplicate labels exist until this has been resolved.
      # https://github.com/github/github/pull/168081
      # https://github.com/github/data-partitioning/issues/370
      # https://github.com/github/issues/issues/1411#issuecomment-799434036
      Issue.from(scope.where("issues.state" => state).select("1"), :_subquery_for_count).async_count
    end

    def self.basic_listing?(components)
      components.all? do |c|
        if c.is_a?(Array)
          # since type: can be used to filter for issue,pr and issue_type,
          # we need make sure that we only return true for issue or pr
          [:is, :state].include?(c.first) || ([:type].include?(c.first) && %w[pr issue].include?(c.second))
        end
      end
    end

    def self.get_state(components)
      is = components.select do |c|
        c.is_a?(Array) && (c.first == :is || c.first == :state)
      end

      state = is.find do |c|
        c.second == "open" || c.second == "closed"
      end.try(:second)

      return state unless state.nil?
      "all"
    end

    # Internal: If feature is enabled and user input @me, return the currently logged
    # in user, otherwise use the input to find user.
    #
    # username_input - either the username to search for, or @me
    # current_user - currently logged in user
    #
    # Returns a User
    def self.derive_user_from_input(username_input, current_user)
      if Search::Query::MACRO_ME.casecmp?(username_input)
        current_user
      else
        User.find_by_login(username_input)
      end
    end

    # is:open, state:open, etc.
    def self.state_scope(components, scope)
      case get_state(components)
      when "open"
        ["open", scope.where(state: "open")]
      when "closed"
        ["closed", scope.where(state: "closed")]
      else
        ["all", scope]
      end
    end

    # is:merged, is:unmerged
    def self.merge_state_scope(components, scope)
      is = components.select do |c|
        c.is_a?(Array) && c.first == :is
      end

      merge_state = is.find do |c|
        c.second == "merged" || c.second == "unmerged"
      end.try(:second)

      join_prs_statement = "INNER JOIN `pull_requests` `prs` ON `prs`.`id` = `issues`.`pull_request_id` AND `issues`.`repository_id` = `prs`.`repository_id`"

      case merge_state
      when "merged"
        scope.
          joins(join_prs_statement).
          where("prs.merged_at IS NOT NULL")
      when "unmerged"
        scope.
          joins(join_prs_statement).
          where("prs.merged_at IS NULL")
      else
        scope
      end
    end

    def self.get_type(components)
      is = components.select do |c|
        c.is_a?(Array) && (c.first == :is || c.first == :type)
      end
      is.find { |c| c.second == "issue" || c.second == "pr" }.try(:second)
    end

    # is:issue, type:issue, etc.
    def self.type_scope(components, scope, repo, force_type: nil)
      return scope.with_pull_requests if force_type == :pull_requests
      return scope.without_pull_requests if force_type == :issues

      # If issues are disabled, never show issues.
      return scope.with_pull_requests if !repo.has_issues

      case get_type(components)
      when "pr"
        scope.with_pull_requests
      when "issue"
        scope.without_pull_requests
      else
        scope
      end
    end

    def self.type_scope_with_has_pull_request(components, scope, repo, force_type: nil)
      return scope.where(has_pull_request: true) if force_type == :pull_requests
      return scope.where(has_pull_request: false) if force_type == :issues

      # If issues are disabled, never show issues.
      return scope.where(has_pull_request: true) if !repo.has_issues

      case get_type(components)
      when "pr"
        scope.where(has_pull_request: true)
      when "issue"
        scope.where(has_pull_request: false)
      else
        scope
      end
    end

    # sort:created-desc, etc.
    def self.sort_scope(sort, scope)
      unless sort
        return scope.order(created_at: "DESC", id: "DESC")
      end

      if sort.starts_with?("reactions")
        sort_by_reactions(sort, scope)
      else
        field, direction = sort.split("-")

        sql_direction = safe_sql_direction(direction)
        if field == "created"
          scope.order(created_at: sql_direction, id: sql_direction)
        else
          scope = scope.sorted_by(field, sql_direction)
          scope.order(id: sql_direction)
        end
      end
    end

    def self.sort_by_reactions(sort, scope)
      # e.g., reactions, reactions-desc
      if matches = /\Areactions(?:-(asc|desc|))?\z/i.match(sort)
        direction = matches[1] || "desc"
        scope = scope.left_outer_joins(:reactions)
      else # e.g., reactions-smile, reactions-smile-asc
        matches = T.must(/\Areactions-(.+?)(?:-(asc|desc|))?\z/i.match(sort))
        reaction = T.must(matches[1]).downcase
        direction = matches[2] || "desc"
        scope = scope.joins("LEFT OUTER JOIN issue_reactions ON issue_reactions.issue_id = issues.id AND issue_reactions.content = #{Reaction.connection.quote(reaction)}")
      end

      sql_direction = safe_sql_direction(direction)
      order_statement = Arel.sql("COUNT(issue_reactions.issue_id) #{sql_direction}")

      scope.group("issues.id").order(order_statement)
    end

    # author:holman, etc.
    def self.author_scope(components, scope, current_user)
      author_component = components.select { |c| c.is_a?(Array) && c.first == :author }.flatten
      author = author_component.try(:second)
      return scope if !author

      if (m = author.match(%r{\Aapp/(.+)}))
        user = Bot.find_by_slug(m[1])
      else
        user = derive_user_from_input(author, current_user)
      end

      return scope.none if !user

      # -author:holman
      return scope.where(["issues.user_id != ?", user.id]) if author_component[2]

      scope.where(user_id: user.id)
    end

    # assignee:login, etc.
    def self.assignee_scope(components, scope, current_user)
      # assignee_component can look like:
      #
      # [:assignee, "login"] when query is "assignee:login"
      # [:assignee, "login", true] when query is "-assignee:login"
      assignee_component = components.detect { |c| c.is_a?(Array) && c.first == :assignee }
      return scope unless assignee_component

      user_login     = assignee_component[1]
      wants_assigned = !assignee_component[2]

      return scope unless user_login

      # api-related assigned wildcard
      return scope.assigned if user_login == "*"

      user = derive_user_from_input(user_login, current_user)
      return scope.none unless user

      if wants_assigned
        # Find all issues assigned to the specified user.
        scope.assigned_to(user)
      else
        # Find all issues that are *not* assigned to the specified user.

        # Use ActiveRecord::Base.sanitize instead of parameters because
        # ActiveRecord doesn't allow parameters in .joins().
        sanitized_assignee_id = Assignment.connection.quote(user.id)

        join = <<-SQL
          LEFT OUTER JOIN `assignments` ON
          `assignments`.`issue_id`    = `issues`.`id` AND
          `assignments`.`assignee_id` = #{sanitized_assignee_id}
        SQL

        scope.joins(join).where(assignments: { assignee_id: nil })
      end
    end

    # label:bug, etc.
    def self.label_scope(repo, components, scope, current_user)
      labels = get_labels(components, current_user).uniq
      return scope if labels.blank?

      if repo
        scope = scope.joins(:labels).merge(repo.labels.with_name(labels))
        # We need to do this HAVING clause because we are approximating ANDing the labels together and a simple
        # labels.lowercase_name IN (?) only handles as OR.
        # This part of the query is heavy so we avoid it if only a single label is passed.
        # https://github.com/github/github/pull/176695
        labels.size > 1 ? scope.group("issues.id").having("COUNT(issues.id) = #{labels.size}") : scope
      else
        scope.labeled(labels)
      end
    end

    def self.label_scope_candidate(repo, components, scope, current_user)
      labels = get_labels(components, current_user).uniq
      return scope if labels.blank?

      if repo
        if labels.size > 1
          # We need to do this HAVING clause because we are approximating ANDing the labels together and a simple
          # labels.lowercase_name IN (?) only handles as OR.
          # This part of the query is heavy so we avoid it if only a single label is passed.
          # https://github.com/github/github/pull/176695
          subquery =
            IssuesLabels.select(:issue_id)
              .joins("INNER JOIN labels ON issues_labels.label_id = labels.id")
              .where(labels: { repository_id: repo.id })
              .merge(repo.labels.with_name(labels))
              .group("issue_id")
              .having("COUNT(DISTINCT issues_labels.label_id) = #{labels.size}")

          scope.joins("INNER JOIN (#{subquery.to_sql}) AS subquery ON issues.id = subquery.issue_id")
        else
          scope.joins(:labels).merge(repo.labels.with_name(labels))
        end
      else
        scope.labeled(labels)
      end
    end

    def self.issue_type_scope(repo, components, scope, user, force_type)
      return scope if force_type == :pull_requests
      issue_type_components = components.select { |c| c.is_a?(Array) && c.first == :type }.flatten
      issue_type_name = issue_type_components.try(:second)
      return scope unless issue_type_name
      return scope unless repo.owner.issue_types_enabled?
      return scope.with_any_issue_type if issue_type_name == "*"

      allowed_types = repo.owner.issue_types
      matching_type = allowed_types.find { |type| type.name.casecmp(issue_type_name).zero? }

      return scope.none if !matching_type
      return scope.none if !matching_type.enabled?

      scope.for_issue_type(matching_type)
    end

    def self.reason_scope(components, scope)
      return scope unless get_type(components) == "issue"

      reason = get_reason(components)
      is_completed = reason == "completed"
      return scope if reason.blank? || !(Issue.state_reasons.include?(reason) || is_completed)

      case get_state(components)
      when "open"
        return scope.none if %w[not_planned completed].include?(reason)
      when "closed"
        return scope.none if ["reopened"].include?(reason)
        reason = nil if is_completed
      else
        # all
        if is_completed
          return scope.where(state: "closed", state_reason: nil)
        end
      end

      scope.where(state_reason: reason)
    end

    # mentions:holman, etc.
    def self.mention_scope(repo, components, scope, current_user)
      mention_components = components.select { |c| c.is_a?(Array) && c.first == :mentions }

      mention_component = mention_components.first
      mention_name = mention_component.try(:second)
      return scope if !mention_name

      user = derive_user_from_input(mention_name, current_user)
      return scope.none if !user

      scope.mentioning(user)
    end

    # milestone:"issues three", etc.
    def self.milestone_scope(repo, components, scope)
      milestone_component = components.select { |c| c.is_a?(Array) && c.first == :milestone }.flatten
      milestone_name = milestone_component.try(:second)
      return scope if !milestone_name

      # api-related milestone wildcard
      return scope.with_any_milestone if milestone_name == "*"

      milestone = repo.milestones.find_by_title(milestone_name)
      return scope.none if !milestone

      # -milestone:v3
      return scope.where(["milestone_id != ? OR milestone_id IS NULL", milestone.id]) if milestone_component[2]

      scope.for_milestone(milestone)
    end

    # Specifically handle three use cases:
    #
    #   no:milestone
    #   no:assignee
    #   no:type
    #
    # Because no:label involves a join table, it becomes unwieldy to support
    # that directly in MySQL.
    def self.no_scope(repo, components, scope, user, force_type)
      no_component = components.select { |c| c.is_a?(Array) && c.first == :no }

      no_component.each do |component|
        filter = component.try(:second)
        return scope if !filter

        # no milestones
        scope = scope.with_no_milestone if filter == "milestone"

        # no assignee
        scope = scope.unassigned if filter == "assignee"

        # no type
        if filter == "type" && force_type != :pull_requests && repo&.owner.issue_types_enabled?
          scope = scope.with_no_issue_type if filter == "type"
        end
      end

      scope
    end

    def self.get_sort(query)
      query.select { |c| c.is_a?(Array) && c.first == :sort }.flatten.try(:second)
    end

    def self.safe_sql_direction(direction)
      direction&.downcase == "asc" ? "asc" : "desc"
    end

    # TODO: this method looks unused
    def self.get_components(query, current_user)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      query.select { |c| !c.first.is_a?(Array) }.map { |c| c.first }.uniq.sort
    end

    def self.get_labels(query, current_user)
      query = ::Search::Queries::IssueQuery.coerce(query, current_user)
      query.select { |c| c.is_a?(Array) && c.first == :label }.map { |lc| lc.try(:second) }.flatten.compact
    end

    def self.get_reason(query)
      reason = query.select { |c| c.is_a?(Array) && c.first == :reason }.flatten.try(:second)
      reason&.parameterize(separator: "_")
    end

    def self.has_any_labels?(query, current_user)
      get_labels(query, current_user).size > 0
    end

    def self.repo_spammy_for?(repo, current_user, show_spam_to_staff)
      repo.spammy? && repo.owner.id != current_user&.id && (!show_spam_to_staff || !current_user.try(:site_admin?))
    end
  end
end
