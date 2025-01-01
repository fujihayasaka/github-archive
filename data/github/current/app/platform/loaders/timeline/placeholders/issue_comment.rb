# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class IssueComment < Platform::Loader
          def self.load(issue_id, viewer)
            self.for(viewer).load(issue_id)
          end

          def initialize(viewer)
            @viewer = viewer
          end

          def fetch(issue_ids)
            fetch_placeholders(issue_ids)
          end

          private

          attr_reader :viewer

          def fetch_placeholders(issue_ids)
            scope = ::IssueComment.
              where(issue_id: issue_ids).
              filter_spam_for(viewer, skip_user_filter_if_not_spammy: true)

            results = scope.pluck(:issue_id, :id, :created_at)

            results_by_issue_id = results.group_by(&:first)
            results_by_issue_id.default_proc = -> (_, _) { [] }

            results_by_issue_id.each_value do |results|
              results.map! do |_, id, created_at|
                ::Timeline::Placeholder::IssueComment.new(
                  id: id, sort_datetimes: [created_at],
                )
              end
            end
          end
        end
      end
    end
  end
end
