# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class DuplicateIssueQuery < IssueQuery
      include IssueSemanticHelper
      include T::Sig

      # Construct a DuplicateIssueQuery.
      # The query will search for issues that are potential duplicates
      # of the provided issue.
      #
      # opts - The options Hash.
      #   :issue  - The candidate issue
      #
      def initialize(opts = {}, &block)
        @issue = T.let(opts.fetch(:issue, nil), ::Issue)

        opts.merge!(
          index: Elastomer::Indexes::IssuesSemantic.new,
          type: "issues",
          ids_to_exclude: [@issue.id],
          sort: [
            %w[_score desc],
            %w[created_at desc],
          ],
          source_fields: %w[issue_id number title],
          per_page: 3,
        )

        current_user = T.let(opts.fetch(:current_user, nil), T.nilable(::User))
        if current_user&.feature_flag_enabled_or_raise?(:elasticsearch_semantic_indexing_issues_show_dupes_cross_repo) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          opts.merge!(
            phrase: "owner:#{@issue.repository&.owner_display_login}",
          )
        end

        super(opts, &block)
      end

      def query_doc
        if current_user&.feature_flag_enabled_or_raise?(:elasticsearch_semantic_indexing_issues_show_dupes_search_individual_fields) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return {
            bool: {
              minimum_should_match: 1,
              should: [
                ({
                  semantic: {
                    field: "title_semantic",
                    query: @issue.title,
                    boost: 1.5,
                  }
                } if @issue.title.present?),
                ({
                  semantic: {
                    field: "body_semantic",
                    query: @issue.title,
                    boost: 1.0
                  }
                } if @issue.title.present?),
                ({
                  semantic: {
                    field: "comment_body_semantic",
                    query: @issue.title,
                    boost: 0.8
                  }
                } if @issue.title.present?),
                ({
                  semantic: {
                    field: "title_semantic",
                    query: @issue.body,
                    boost: 1.5,
                  }
                } if @issue.body.present?),
                ({
                  semantic: {
                    field: "body_semantic",
                    query: @issue.body,
                    boost: 1.0
                  }
                } if @issue.body.present?),
                ({
                  semantic: {
                    field: "comment_body_semantic",
                    query: @issue.title,
                    boost: 0.8
                  }
                } if @issue.body.present?),
              ].compact
            },
          }
        end

        {
          bool: {
            minimum_should_match: 1,
            should: [
              # Search by both title and body to identify potential duplicates
              ({
                semantic: {
                  field: "semantic_search_field",
                  query: @issue.title,
                  boost: 1.5,
                }
              } if @issue.title.present?),
              ({
                semantic: {
                  field: "semantic_search_field",
                  query: @issue.body,
                }
              } if @issue.body.present?),
            ].compact,
          },
        }
      end

      # Search for potential duplicates of the provided issue.
      sig { params(issue: ::Issue, kwargs: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def self.find_duplicates_of(issue:, **kwargs)
        search_result = self.new(issue:, **kwargs).execute.results

        search_result.each_with_index.map do |hit, index|
          {
            id: hit.dig("_source", "issue_id"),
            number: hit.dig("_source", "number"),
            title: hit.dig("_source", "title"),
            index:,
            score: hit.dig("_score"),
          }
        end
      end

      # Validate user-indicated duplicates for the provided issue.
      sig { params(issue: ::Issue, kwargs: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.validate_duplicates_of(issue:, **kwargs)
        duplicate_issue_rel = DuplicateIssue
          .preload(:issue, :canonical_issue)
          .where(repository_id: issue.repository_id)
          .marked_as_duplicate
        duplicate_issues = duplicate_issue_rel.with_duplicate_issue(issue.id)
          .or(duplicate_issue_rel.with_canonical_issue(issue.id))
          .limit(50)
          .flat_map { |di| [di.issue, di.canonical_issue] }
          .compact
          .uniq

        known_duplicates = duplicate_issues - [issue]
        potential_duplicates = find_duplicates_of(**T.unsafe({ issue:, **kwargs }))

        known_duplicates.map do |duplicate|
          match = potential_duplicates.find { |p| p[:id] == duplicate.id }

          {
            number: duplicate.number,
            title: duplicate.title,
            url: duplicate.permalink,
            found: \
              if match
                {
                  index: match&.dig(:index),
                  score: match&.dig(:score),
                }
              end,
          }
        end
      end

      # Validate user-indicated duplicate issues for the provided repository.
      sig { params(repository: ::Repository, kwargs: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def self.validate_duplicates_for(repository:, **kwargs)
        duplicate_issues = DuplicateIssue
          .preload(:issue, :canonical_issue)
          .where(repository:)
          .marked_as_duplicate
          .limit(100)

        found_forward = 0
        found_reverse = 0

        details = duplicate_issues.reduce([]) do |memo, di|
          # Try to find the user-indicated duplicate for this issue
          dupes = find_duplicates_of(**T.unsafe({ issue: T.must(di.issue), **kwargs }))
          match = dupes.find { |it| it[:id] == di.canonical_issue_id }
          memo << {
            number: di.issue&.number,
            title: di.issue&.title,
            url: di.issue&.permalink,
            expected: {
              number: di.canonical_issue&.number,
            },
            found: \
              if match
                found_forward += 1
                {
                  index: match&.dig(:index),
                  score: match&.dig(:score),
                }
              end,
          }

          # Reverse search and try to find _this_ issue from the duplicate
          dupes = find_duplicates_of(**T.unsafe({ issue: T.must(di.canonical_issue), **kwargs }))
          match = dupes.find { |it| it[:id] == di.issue_id }
          memo << {
            number: di.canonical_issue&.number,
            title: di.canonical_issue&.title,
            url: di.canonical_issue&.permalink,
            expected: {
              number: di.issue&.number,
            },
            found: \
              if match
                found_reverse += 1
                {
                  index: match&.dig(:index),
                  score: match&.dig(:score),
                }
              end,
          }
        end

        {
          known_duplicates: duplicate_issues.count,
          found_forward:,
          found_forward_ratio: found_forward.to_f / duplicate_issues.count,
          found_reverse:,
          found_reverse_ratio: found_reverse.to_f / duplicate_issues.count,
          details:,
        }
      end
    end
  end
end
