# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class LabeledPullRequestNextComponent < PullRequestBaseComponent

      def render?
        label.present? && user_feature_enabled?(:feeds_v2)
      end

      private

      def heading_icon
        case state
        when :merged
          { name: :"feed-merged", color: :done }
        when :open
          is_draft? ? { name: :"feed-pr-draft", exported: true } : { name: :"feed-pr-open", exported: true }
        when :closed
          { name: :"feed-pr-closed", exported: true }
        end
      end

      def label
        item.label
      end
    end
  end
end
