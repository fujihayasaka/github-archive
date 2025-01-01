# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class PushEventComponent < BaseComponent
      delegate :branch_name, :shas, to: :item, private: true
      delegate :push_type, to: :subject, private: true

      private

      def render?
        return false unless feature_enabled?

        subject.present?
      end

      def heading_icon
        { name: :"code", color: :open }
      end

      def show_n_more_commits_link?
        commits_count > 2
      end

      def branch_creation?
        push_type == "branch_creation"
      end

      def branch_deletion?
        push_type == "branch_deletion"
      end

      def commits_count
        item.total_commits_count
      end

      def shown_shas
        shas.first([commits_count, 2].min)
      end

      def push_comparison_url
        range = [subject.before, subject.after].join("...")
        compare_path(repository, range)
      end

      def feature_enabled?
        user_feature_enabled?(:conduit_push_events_in_feed)
      end

      def related_card_component(related_item:)
        related_item_push_type = related_item.subject&.push_type
        if related_item_push_type == "branch_creation"
          Feed::Cards::CreatePushComponent
        elsif related_item_push_type == "branch_deletion"
          Feed::Cards::DeletePushComponent
        else
          Feed::Cards::PushEventComponent
        end
      end
    end
  end
end
