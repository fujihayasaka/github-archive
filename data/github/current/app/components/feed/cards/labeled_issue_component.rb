# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class LabeledIssueComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::IssueViewComponentMethods

      def render?
        label && super
      end

      def heading_icon
        if issue.closed?
          if issue.unplanned?
            return { name: :"skip", color: :muted }
          end
          return { name: :"issue-closed", color: :done }
        end
        { name: :"issue-opened", color: :open }
      end

      def label
        item.label
      end
    end
  end
end
