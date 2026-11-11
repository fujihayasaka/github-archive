# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Timeline < TimelineItems
      def self.substitute_legacy_types(types)
        types.map { |type| type == Objects::Commit ? Objects::PullRequestCommit : type }
      end

      def total_count
        page.async_filtered_count
      end

      protected

      sig { returns(::Issues::Timeline::Timeline) }
      def timeline
        @items.timeline
      end

      def nodes
        page.async_entries.then do |entries|
          entries.map do |entry|
            if entry.is_a?(Platform::Models::PullRequestCommit)
              entry.commit.tap do |commit|
                commit.repository = @parent.repository
              end
            else
              entry
            end
          end
        end
      end
    end
  end
end
