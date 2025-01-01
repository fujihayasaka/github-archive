# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class LabeledPullRequestComponent < ApplicationComponent
      include FeedCards::PullRequestViewComponentMethods

      def render?
        label.present?
      end

      private

      def heading_icon
        case state
        when :merged
          { name: :"feed-merged", color: :done }
        when :open
          is_draft? ? { name: :"git-pull-request-draft", color: :default } : { name: :"git-pull-request", color: :open }
        when :closed
          { name: :"git-pull-request-closed", color: :closed }
        end
      end

      def label
        item.label
      end
    end
  end
end
