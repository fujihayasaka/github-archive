# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module PullRequest
      class ReviewThreads < Platform::Loader
        def self.load(pull_request_id, viewer, path: nil, subject_type: nil, outdated: nil)
          self.for(viewer, path: path, subject_type: subject_type, outdated: outdated).load(pull_request_id)
        end

        def initialize(viewer, path: nil, subject_type: nil, outdated: nil)
          @viewer = viewer
          @path = path
          @subject_type = subject_type
          @outdated = outdated
        end

        private

        attr_reader :viewer

        def fetch(pull_request_ids)
          scope = ::PullRequestReviewThread.
            where(pull_request_id: pull_request_ids).
            visible_to(viewer)

          scope = scope.where(path: @path) if @path.present?
          scope = scope.where(subject_type: @subject_type) if @subject_type.present?
          scope = scope.where(outdated: @outdated) if !@outdated.nil?

          scope.group_by(&:pull_request_id).tap do |results|
            results.default_proc = -> (_, _) { [] }
          end
        end
      end
    end
  end
end
