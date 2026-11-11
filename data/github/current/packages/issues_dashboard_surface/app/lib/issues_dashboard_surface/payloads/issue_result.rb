# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  module Payloads
    class IssueResult < T::Struct
      class IssueTypeInfo < T::Struct
        const :id, Integer
        const :name, String
        const :color, String
      end

      class MilestoneInfo < T::Struct
        const :title, String
        const :url, String
      end

      class IssueAuthor < T::Struct
        const :login, String
        const :name, T.nilable(String)
        const :avatarUrl, String
        const :resourcePath, String
        const :typename, String
        const :isCopilot, T::Boolean
        const :isAgent, T::Boolean
      end

      class IssueAssignee < T::Struct
        const :id, Integer
        const :login, String
        const :name, T.nilable(String)
        const :avatarUrl, String
        const :profileResourcePath, String
        const :isCopilot, T::Boolean
        const :isAgent, T::Boolean
      end

      const :assignees, T::Array[IssueAssignee]
      const :author, IssueAuthor
      const :closed, T::Boolean
      const :closedAt, T.nilable(String)
      const :commentCount, Numeric
      const :createdAt, String
      const :labels, T::Array[DashboardSurface::Payloads::Label]
      const :id, Integer
      const :issueType, T.nilable(IssueTypeInfo)
      const :itemType, String
      const :milestone, T.nilable(MilestoneInfo)
      const :number, Integer
      const :permalink, T.nilable(String)
      const :repoNameWithOwner, T.nilable(String)
      const :state, T.nilable(String)
      const :stateReason, T.nilable(String)
      const :title, String
      const :titleHtml, String
      const :updatedAt, String

      sig { params(issue: Issue).returns(IssueResult) }
      def self.serialize(issue)
        state_reason = issue.state_reason&.to_s&.upcase
        # The DB stores nil for issues closed before state_reason was added.
        # Treat nil on a closed issue as COMPLETED, matching the GraphQL layer.
        state_reason = "COMPLETED" if state_reason.nil? && issue.closed?

        author = issue.safe_user
        issue_type = issue.issue_type
        milestone = issue.milestone
        author_flags = bot_flags(author)

        IssueResult.new(
          assignees: issue.assignees.map do |assignee|
            assignee_flags = bot_flags(assignee)
            IssueAssignee.new(
              id: assignee.id,
              login: assignee.display_login,
              name: assignee.name,
              avatarUrl: assignee.primary_avatar_url,
              profileResourcePath: "/#{assignee.display_login}",
              isCopilot: assignee_flags.is_copilot,
              isAgent: assignee_flags.is_agent,
            )
          end,
          author: IssueAuthor.new(
            login: author.display_login,
            name: author.respond_to?(:name) ? author.name : nil,
            avatarUrl: author.primary_avatar_url,
            resourcePath: "/#{author.display_login}",
            typename: author.is_a?(Bot) ? "Bot" : "User",
            isCopilot: author_flags.is_copilot,
            isAgent: author_flags.is_agent,
          ),
          closed: issue.closed?,
          closedAt: issue.closed_at&.iso8601,
          commentCount: issue.issue_comments_count || 0,
          createdAt: issue.created_at.iso8601,
          updatedAt: issue.updated_at.iso8601,
          labels: issue.sorted_labels.map do |label|
            DashboardSurface::Payloads::Label.new(
              color: label.color,
              description: label.description,
              id: label.id,
              name: label.name,
              nameHtml: label.name_html,
            )
          end,
          id: issue.id,
          issueType: issue_type ? IssueTypeInfo.new(id: issue_type.id, name: issue_type.name, color: issue_type.color) : nil,
          itemType: "issue",
          milestone: milestone ? MilestoneInfo.new(title: milestone.title, url: milestone.url) : nil,
          number: issue.number,
          permalink: issue.permalink,
          repoNameWithOwner: issue.repository&.full_name,
          state: issue.state&.to_s&.upcase,
          stateReason: state_reason,
          title: issue.title,
          titleHtml: serialize_title_html(issue.title),
        )
      end

      sig { params(title: String).returns(String) }
      def self.serialize_title_html(title)
        sanitized = title.dup
        while sanitized.start_with?("\0")
          sanitized = T.must(sanitized[1..-1])
        end
        GitHub::Goomba::TitleMarkdownFilter.call(sanitized)
      end

      class BotFlags < T::Struct
        const :is_copilot, T::Boolean
        const :is_agent, T::Boolean
      end

      sig { params(user: User).returns(BotFlags) }
      def self.bot_flags(user)
        return BotFlags.new(is_copilot: false, is_agent: false) unless user.is_a?(Bot)

        integration = user.integration
        is_copilot = integration.present? && Apps::Privileged.capable?(:is_copilot, app: integration)
        is_agent = AgenticApp.agent_for_bot_id(user.id).present?
        BotFlags.new(is_copilot: is_copilot, is_agent: is_agent)
      end
    end
  end
end
