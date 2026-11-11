# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssuesAndPullRequests < Resolvers::Base
      argument :order_by, Inputs::IssueOrder, "Ordering options for issues and pull requests returned from the connection.", required: false,
               default_value: { field: "created_at", direction: "DESC" }
      argument :filter_by, Inputs::IssueAndPullRequestFilters, "Filtering options for issues and pull requests returned from the connection.", required: false

      type Connections.define(Unions::IssueOrPullRequest), null: false

      SORT_FIELD_MAPPINGS = {
        "created_at" => "created",
        "updated_at" => "updated",
        "comments"   => "comments",
      }.freeze

      def resolve(**arguments)
        components = filter_components(arguments)
        phrase = Search::Queries::IssueQuery.stringify(components)
        Search::Queries::IssueQuery.new(
          current_user: @context[:viewer],
          phrase: phrase,
          context: "graphql-resolver-issues-and-pull-requests",
        )
      end

      def filter_components(arguments)
        components = T.let([[:archived, false]], Array)

        if filter = arguments[:filter_by]
          components << [:is, filter[:type]] if filter[:type]
          components << [:is, filter[:state]] if filter[:state]
          components << [:label, filter[:label]] if filter[:label]
          components << [:"reviewed-by", filter[:reviewed_by]] if filter[:reviewed_by]
          components << [:"review-requested", filter[:review_requested]] if filter[:review_requested]
          components << [:review, filter[:review_state]] if filter[:review_state]
          components << [:assignee, filter[:assignee]] if filter[:assignee]
          components << [:author, filter[:author]] if filter[:author]
          components << [:milestone, filter[:milestone]] if filter[:milestone]
          components << [:mentions, filter[:mentions]] if filter[:mentions]
          if filter[:repository]
            filter[:repository].each do |repo|
              components << [:repo, repo]
            end
          end
        end

        if order_by = arguments[:order_by]
          field = SORT_FIELD_MAPPINGS[order_by[:field].downcase]
          component = [field, order_by[:direction].downcase].join("-")
          components << [:sort, component]
        end

        components
      end

    end
  end
end
