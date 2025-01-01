# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class PullRequestReview < Platform::Loader
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
            scope = ::PullRequestReview.
              where(pull_request_id: pull_request_ids).
              visible_in_timeline_for(viewer)

            selected_attributes = [:pull_request_id, :id, :created_at, :submitted_at]
            results = scope.pluck(*selected_attributes)

            results_by_pull_request_id = results.group_by(&:first)
            results_by_pull_request_id.default_proc = ->(_, _) { [] }

            results_by_pull_request_id.each_value do |results|
              results.map! do |_, id, created_at, submitted_at|
                ::Timeline::Placeholder::PullRequestReview.new(
                  id: id,
                  sort_datetimes: [submitted_at || created_at],
                  filter_datetime: submitted_at || created_at,
                )
              end
            end
          end
        end
      end
    end
  end
end
