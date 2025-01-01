# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class LegacyPullRequestReviewThread < Platform::Loader
          def self.load(pull_request_id, viewer)
            self.for(viewer).load(pull_request_id)
          end

          def initialize(viewer)
            @viewer = viewer
          end

          def fetch(pull_request_ids)
            fetch_placeholders(pull_request_ids)
          end

          private

          attr_reader :viewer

          def fetch_placeholders(pull_request_ids)
            scope = ::PullRequestReviewThread.
              where(pull_request_id: pull_request_ids).
              legacy.
              visible_to(viewer)

            selected_attributes = [:pull_request_id, :id, :created_at]
            results = scope.pluck(*selected_attributes)

            results_by_pull_request_id = results.group_by(&:first)
            results_by_pull_request_id.default_proc = ->(_, _) { [] }

            results_by_pull_request_id.each_value do |results|
              results.map! do |_, id, created_at|
                placeholder = ::Timeline::Placeholder::PullRequestReviewThread.new(
                  id: ::PullRequestReviewThread.id_for(thread_id: id, version: 2),
                  sort_datetimes: [created_at],
                )
                placeholder.database_id = id

                placeholder
              end
            end
          end
        end
      end
    end
  end
end
