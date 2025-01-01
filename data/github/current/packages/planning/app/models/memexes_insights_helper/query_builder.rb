# typed: true
# frozen_string_literal: true

module MemexesInsightsHelper
  class QueryBuilder
    def initialize(
      memex_org:,
      date_selector:,
      project_item_id_clause:,
      query_labels_historical_data:,
      repo_ids_clause: nil,
      group_by: {},
      aggregate: {},
      include_archived: nil
    )
      @query_components = QueryComponents.new(memex_org, date_selector)
      @repo_ids_clause = repo_ids_clause
      @project_item_id_clause = project_item_id_clause
      @group_by = group_by
      @aggregate = aggregate
      @include_archived = include_archived
      @query_labels_historical_data = query_labels_historical_data
    end

    def build
      if @project_item_id_clause.present?
        @query_components.where_q << @project_item_id_clause
      end

      if @repo_ids_clause.present?
        @query_components.where_q << @repo_ids_clause
      end

      unless @include_archived
        @query_components.where_q << "Archived = 0"
      end

      @query_components.select_q << aggregate_select

      if @group_by.present?
        case @group_by[:data_type]
        when "singleSelect"
          single_select
        when "iteration"
          iteration
        when "repository"
          repository
        when "labels"
          labels
        when "milestone"
          milestone
        when "assignees"
          assignees
        end
      end

      <<-QUERY.squish
        SELECT #{@query_components.select_q.join(", ")}
        FROM ProjectItemSnapshot P
        #{@query_components.join_q.map(&:to_s).join("\n")}
        WHERE #{@query_components.where_q.join("\nAND ")}
        GROUP BY #{@query_components.group_q.join(", ")}
        #{"ORDER BY #{@query_components.order_q.join(", ")}" if @query_components.order_q.present?}
      QUERY
    end

    # Sanitizes and escapes a column name for the Insights service to prevent SQL injection.
    def self.escape_column_name(name)
      escaped = name.dup
      #if [] are present in column name, adding extra ] to escape square brackets
      escaped.gsub!("]", "]]")
      # remove newlines with whitespace
      escaped.gsub!("\n", " ")
      escaped.gsub!("\r", " ")
      "[#{escaped}]"
    end

    private

    def aggregate_select
      return "COUNT(P.ProjectItemId) as count" unless @aggregate.present?

      aggregate_column, agg_type = @aggregate.values_at(:column, :aggregation_type)
      aggregate_column = self.class.escape_column_name(aggregate_column)
      "COALESCE(#{agg_type}(P.#{aggregate_column}), 0) as [#{agg_type}]"
    end

    def single_select
      group_by_column = self.class.escape_column_name(@group_by[:column])
      group_by_column_key = self.class.escape_column_name(@group_by[:column] + "Key")

      # Status is a special case because it's a system, single-select field that's included in the ProjectItems table.
      # It also requires sorting DESC to match the expected look of the burn-up chart.
      if group_by_column == "[Status]"
        @query_components.select_q.concat(["COALESCE(P.Status, 'No Status') as Status"])
        @query_components.join_q.concat([])
        @query_components.group_q.concat(["P.Status", "P.StatusRank"])
        @query_components.order_q.concat(["P.StatusRank DESC"])
        return
      end

      @query_components.select_q.concat(["COALESCE(S.Name, 'No Value') as #{group_by_column}"])
      @query_components.join_q.concat([JoinTable.new("SingleSelectColumnSetting", "LEFT OUTER JOIN", "S.SingleSelectKey = P.#{group_by_column_key}", "S")])
      @query_components.group_q.concat(["S.Name", "S.OptionRank"])
      @query_components.order_q.concat(["S.OptionRank"])
    end

    def iteration
      group_by_column = self.class.escape_column_name(@group_by[:column])
      group_by_column_key = self.class.escape_column_name(@group_by[:column] + "Key")

      @query_components.select_q.concat(["COALESCE(I.Name, 'No Iteration') as #{group_by_column}"])
      @query_components.join_q.concat([JoinTable.new("Iteration", "LEFT OUTER JOIN", "I.IterationKey = P.#{group_by_column_key}", "I")])
      @query_components.group_q.concat(["I.Name", "I.StartDateKey"])
      @query_components.order_q.concat(["I.StartDateKey"])
    end

    def repository
      group_by_column = @group_by[:column]

      @query_components.select_q.concat(["COALESCE(P.RepositoryName, 'No Repository') as Repository"])
      @query_components.group_q.concat(["P.RepositoryName", "P.RepositoryId"])
      @query_components.order_q.concat(["P.RepositoryName"])
    end

    def labels
      @query_components.select_q.concat(["COALESCE(L.Name, 'No Labels') as Label"])

      if @query_labels_historical_data.present?
        @query_components.join_q.concat([JoinTable.new("ProjectItemLabelMapSnapshot", "LEFT OUTER JOIN", "P.ProjectItemId = M.ProjectItemId AND P.DateKey = M.DateKey", "M"), JoinTable.new("Label", "LEFT OUTER JOIN", "M.LabelId = L.LabelId", "L")])
      else
        @query_components.join_q.concat([JoinTable.new("IssueLabelMap", "LEFT OUTER JOIN", "P.ContentId = M.IssueId", "M"), JoinTable.new("Label", "LEFT OUTER JOIN", "M.LabelId = L.LabelId", "L")])
      end

      @query_components.group_q.concat(["L.Name", "L.LabelId"])
      @query_components.order_q.concat(["L.Name"])
    end

    def milestone
      @query_components.select_q.concat(["COALESCE(M.Title, 'No Milestone') as Milestone"])
      @query_components.join_q.concat([JoinTable.new("Milestone", "LEFT OUTER JOIN", "P.MilestoneId = M.MilestoneId", "M")])
      @query_components.group_q.concat(["M.Title", "M.MilestoneId"])
      @query_components.order_q.concat(["M.Title"])
    end

    def assignees
      @query_components.select_q.concat(["COALESCE(U.Login, 'No Assignees') as Assignee"])
      @query_components.join_q.concat([JoinTable.new("ProjectItemUserMapSnapshot", "LEFT OUTER JOIN", "P.ProjectItemId = M.ProjectItemId AND P.DateKey = M.DateKey", "M"), JoinTable.new("Users", "LEFT OUTER JOIN", "M.UserId = U.UserId", "U")])
      @query_components.group_q.concat(["U.Login"])
      @query_components.order_q.concat(["U.Login"])
    end
  end
end
