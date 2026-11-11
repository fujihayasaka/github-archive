# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ViewedUserReviewedFiles < Platform::Loader
      def self.load(pull_request_id, viewer)
        self.for(viewer).load(pull_request_id)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      def fetch(pull_request_ids)
        # Return empty results for anonymous users
        return build_empty_results(pull_request_ids) if @viewer.nil?

        scope = UserReviewedFile.not_dismissed.where(pull_request_id: pull_request_ids, user_id: @viewer.id)

        scope.group_by(&:pull_request_id).tap do |results|
          results.default_proc = -> (_, _) { [] }
        end
      end

      private

      def build_empty_results(pull_request_ids)
        {}.tap do |results|
          results.default_proc = -> (_, _) { [] }
        end
      end
    end
  end
end
