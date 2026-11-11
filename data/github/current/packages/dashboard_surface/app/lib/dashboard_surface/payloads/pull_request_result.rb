# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    class Author < T::Struct # rubocop:disable Rails/ModuleNaming
      const :displayLogin, String
    end

    class AgentAttributedUser < T::Struct # rubocop:disable Rails/ModuleNaming
      const :displayLogin, String
    end

    class Assignee < T::Struct # rubocop:disable Rails/ModuleNaming
      const :login, String
      const :avatarUrl, String
    end

    class PullRequestResult < T::Struct
      const :assignees, T::Array[Assignee]
      const :author, Author
      const :authoredByAgent, T.nilable(T::Boolean)
      const :category, T.nilable(String)
      const :commentCount, Numeric
      const :commitHeadShaChannel, T.nilable(String)
      const :agentAttributedUser, T.nilable(AgentAttributedUser)
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
      const :stackPosition, T.nilable(Integer)
      const :stackSize, T.nilable(Integer)
      # The state of the pull request (OPEN, CLOSED, MERGED)
      const :state, T.nilable(String) # OPEN, CLOSED, MERGED
      const :title, String
      const :titleHtml, String
      const :updatedAt, String

      # `viewer` is the user looking at the page; we use it to evaluate per-viewer
      # feature flag rollouts. It must be threaded through from the controller
      # rather than read from any global so the payload stays a pure data builder.
      sig { params(pull_request: PullRequest, category: T.nilable(String), viewer: T.nilable(User)).returns(PullRequestResult) }
      def self.serialize(pull_request, category: nil, viewer: nil)
        stacks_enabled = PullRequests::Stacks.enabled?(pull_request.repository)
        if stacks_enabled
          GitHub::PrefillAssociations.prefill_associations(pull_request, :stack)
        end
        agent_author_expansion_enabled = !!viewer&.feature_flag_enabled?(:agent_author_search_expansion_ui_pulls, default: false)
        # Surfaces the user that provisioned the agent which authored this PR.
        # Gated per-viewer; nil for anonymous viewers and when the flag is off.
        agent_attributed_user =
          if agent_author_expansion_enabled
            attributed = pull_request.pull_request_copilot_attributions.first&.user
            attributed && AgentAttributedUser.new(displayLogin: attributed.display_login)
          end
        PullRequestResult.new(
          assignees: pull_request.assignees.map do |assignee|
            Assignee.new(
              login: assignee.display_login,
              avatarUrl: assignee.primary_avatar_url,
            )
          end,
          author: Author.new(
            displayLogin: pull_request.safe_user.display_login,
          ),
          authoredByAgent: agent_author_expansion_enabled ? pull_request.authored_by_agent? : nil,
          category: category,
          commitHeadShaChannel: GitHub::WebSocket::Channels.signed_commit(
            pull_request.base_repository,
            pull_request.head_sha,
          ),
          commentCount: pull_request.total_comments,
          agentAttributedUser: agent_attributed_user,
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
          stackPosition: stacks_enabled ? pull_request.stack_position : nil,
          stackSize: stacks_enabled ? pull_request.stack_size : nil,
          state: pull_request.state&.to_s&.upcase,
          title: pull_request.title,
          titleHtml: pull_request.title_html,
        )
      end
    end
  end
end
