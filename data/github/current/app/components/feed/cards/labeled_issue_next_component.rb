# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class LabeledIssueNextComponent < IssueBaseComponent
      def render?
        label && super
      end

      def heading_icon
        if issue.closed?
          if issue.unplanned?
            { name: :"skip", color: :muted }
          else
            { name: :"feed-issue-closed", exported: true }
          end
        elsif issue.state_reason_reopened?
          { name: :"feed-issue-reopen", exported: true }
        else
          { name: :"feed-issue-open", exported: true }
        end
      end

      def label
        item.label
      end
    end
  end
end
