# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class PullRequestRevisionMarker < Platform::Loader
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
            return Hash.new { [] } if viewer.nil?

            scope = ::LastSeenPullRequestRevision.latest_for(pull_request_ids, viewer.id)

            selected_attributes = [:pull_request_id, :last_revision]
            results = scope.pluck(*selected_attributes)

            results_by_pull_request_id = results.group_by(&:first)
            results_by_pull_request_id.default_proc = ->(_, _) { [] }

            results_by_pull_request_id.each_value do |results|
              next if results.empty?

              # We always only want to return one marker per pull request
              _, last_revision = results.first

              results.clear
              results << ::Timeline::Placeholder::PullRequestRevisionMarker.new(
                last_seen_commit_oid: last_revision,
              )
            end
          end
        end
      end
    end
  end
end
