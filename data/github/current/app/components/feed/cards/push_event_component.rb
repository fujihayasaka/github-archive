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
        subject.present? && commit_details_load?
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

      FEED_RPC_TIMEOUT_SECONDS = 0.1

      memoize def commits_count
        repo = subject.repository
        unless repo
          @failed_to_load_commits = true
          return 0
        end

        repo.rpc.with_timeout(FEED_RPC_TIMEOUT_SECONDS) do
          item.total_commits_count
        end
      rescue GitRPC::Timeout
        @failed_to_load_commits = true
        0
      end

      memoize def shown_shas
        # Getting total_commits_count will cache commits, saving an extra rpc call in commits_summary
        count = commits_count

        shas.first([count, 2].min)
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

      def commit_details_load?
        commits_count

        item.is_a?(::Conduit::FeedItem::PushEvent) && !@failed_to_load_commits
      end
    end
  end
end
