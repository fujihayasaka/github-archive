# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    class Label < T::Struct # rubocop:disable Rails/ModuleNaming
      const :color, T.nilable(String)
      const :description, T.nilable(String)
      const :id, Integer
      const :name, String
      const :nameHtml, T.nilable(String)
    end

    class Author < T::Struct # rubocop:disable Rails/ModuleNaming
      const :displayLogin, String
    end

    class PullRequestResult < T::Struct
      const :author, Author
      const :category, T.nilable(String)
      const :commentCount, Numeric
      const :createdAt, String
      # The display state of the pull request (used for icons)
      const :displayState, T.nilable(String)
      const :headSha, T.nilable(String)
      const :labels, T::Array[Label]
      const :id, Integer
      const :isDraft, T::Boolean
      const :isReadByCurrentUser, T::Boolean
      const :number, Integer
      const :permalink, T.nilable(String)
      const :repoNameWithOwner, T.nilable(String)
      # The state of the pull request (OPEN, CLOSED, MERGED)
      const :state, T.nilable(String) # OPEN, CLOSED, MERGED
      const :title, String
      const :titleHtml, String
      const :updatedAt, String

      sig { params(pull_request: PullRequest, category: T.nilable(String)).returns(PullRequestResult) }
      def self.serialize(pull_request, category: nil)
        PullRequestResult.new(
          author: Author.new(
            displayLogin: pull_request.safe_user.display_login,
          ),
          category: category,
          commentCount: pull_request.total_comments,
          createdAt: pull_request.created_at.iso8601,
          updatedAt: pull_request.updated_at.iso8601,
          displayState: PullRequest::Icon::State.for_pull_request(pull_request)&.to_s&.upcase,
          headSha: pull_request.head_sha,
          # The pull request must have an issue because results passed into this serializer were returned from finding
          # an issue
          labels: T.must(pull_request.issue).sorted_labels.map do |label|
            Label.new(
              color: label.color,
              description: label.description,
              id: label.id,
              name: label.name,
              nameHtml: label.name_html,
            )
          end,
          id: pull_request.id,
          isDraft: pull_request.draft?,
          isReadByCurrentUser: !!T.must(pull_request.issue).read_by_current_user,
          number: pull_request.number,
          permalink: pull_request.permalink,
          repoNameWithOwner: pull_request.repository&.full_name,
          state: pull_request.state&.to_s&.upcase,
          title: pull_request.title,
          titleHtml: pull_request.title_html,
        )
      end
    end
  end
end
