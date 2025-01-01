# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class PushEventComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      delegate :branch_name, :shas, to: :item, private: true
      delegate :push_type, to: :subject, private: true

      private

      def render?
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

      memoize def commits_count
        GitHub.dogstats.distribution_time("conduit.feed_commits_count") do
          item.total_commits_count
        end
      end

      memoize def shown_shas
        # Getting total_commits_count will cache commits, saving an extra rpc call in commits_summary
        count = commits_count

        GitHub.dogstats.distribution_time("conduit.shown_shas") do
          shas.first([count, 2].min)
        end
      end

      memoize def push_comparison_url
        range = [subject.before, subject.after].join("...")
        compare_path(repository, range)
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
