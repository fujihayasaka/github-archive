# typed: true
# frozen_string_literal: true

module ExploreFeed
  class RepositoryGoodFirstIssue
    ISSUE_BODY_CHARACTER_LIMIT = 400
    LABEL_BASED_SOURCE_NAME = "label_based"
    VALID_SOURCE_NAMES = %w[label_based ml_based].freeze

    class << self
      def fetch_by_repo_id(repo_id)
        raw_issues = raw_good_first_issues(repo_id)["issues"]
        raw_issue_ids = raw_issues.map { |issue| issue["issue_id"] }
        issues = Issue.where(id: raw_issue_ids).index_by(&:id)
        Collection.new(
          raw_issues.map do |attributes|
            new(attributes, original_issue: issues[attributes["issue_id"]])
          end
        ).sorted
      end

      private

      def raw_good_first_issues(repo_id)
        cache_key = ["good_first_issues", repo_id, Date.current.iso8601].join(".")

        GitHub.cache.fetch(cache_key) do
          return { "issues" => [] } if GitHub.enterprise?

          { "issues" => good_first_issues_for_repo(repo_id).map do |issue_id|
                          {
                            "issue_id" => issue_id,
                            "score" => 1,
                            "sources" => [LABEL_BASED_SOURCE_NAME],
                          }
                        end
          }
        end
      end

      def good_first_issues_for_repo(repo_id)
        repo = Repositories::Public.find_active!(repo_id)
        # TODO: Provide a better type
        label = T.cast(repo.labels, T.untyped).good_first_issue

        if label.present?
          repo.issues.labeled(label).pluck(:id)
        else
          []
        end
      end
    end

    delegate(
      :body,
      :comments,
      :created_at,
      :id,
      :labels,
      :number,
      :open?,
      :permalink,
      :present?,
      :repository,
      :safe_user,
      :title,
      :user,
      to: :original_issue,
      allow_nil: true,
    )
    delegate(
      :login,
      :primary_avatar_url,
      to: :safe_user,
      allow_nil: true,
      prefix: :author,
    )
    delegate :maintained?, :public?, to: :repository, allow_nil: true, prefix: true

    def initialize(attributes, original_issue: nil)
      @attributes = attributes
      @_original_issue = original_issue
    end

    def score
      attributes["score"]
    end

    def recommendable?
      recommendable_checks = [
        present?,
        open?,
        repository_public?,
        repository_maintained?,
        has_valid_sources?,
      ]

      recommendable_checks.all?
    end

    def truncated_body_html
      cache_key = [
        "good_first_issues",
        "truncated_body_html",
        id,
        Date.current.iso8601,
      ].join("-")

      GitHub.cache.fetch(cache_key) do
        GitHub::Goomba::MarkdownPipeline.to_html(
          body.truncate(ISSUE_BODY_CHARACTER_LIMIT, omission: ""),
        )
      end
    end

    def original_issue
      @_original_issue ||= ::Issue.find_by(id: attributes["issue_id"]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    private

    attr_reader :attributes

    def has_valid_sources?
      (VALID_SOURCE_NAMES & sources).any?
    end

    def sources
      attributes["sources"] || [LABEL_BASED_SOURCE_NAME]
    end

    class Collection
      include Enumerable

      REPOSITORY_CARD_LIMIT = 4
      REPOSITORY_CARD_VISIBLE_LIMIT = 3
      EXPLORE_MAILER_LIMIT = 2

      def initialize(issues)
        @issues = issues
      end

      def each(&block)
        issues.each(&block)
      end

      def size
        issues.count
      end

      def sorted
        sorted_issues = issues
          .sort_by(&:score)
          .reverse
          .lazy

        self.class.new(sorted_issues)
      end

      def limit(limit)
        limited_issues = issues
          .first(limit)

        self.class.new(limited_issues)
      end

      def recommendable
        recommendable_issues = issues
          .select(&:recommendable?)

        self.class.new(recommendable_issues)
      end

      def repository_card_issues
        issues_for_repository_card = issues
          .first(REPOSITORY_CARD_LIMIT)

        self.class.new(issues_for_repository_card)
      end

      def explore_mailer_issues
        issues_for_explore_mailer = issues
          .first(EXPLORE_MAILER_LIMIT)

        self.class.new(issues_for_explore_mailer)
      end

      def show_link_to_more?
        issues.size >= REPOSITORY_CARD_LIMIT
      end

      private

      attr_accessor :issues
    end
  end
end
