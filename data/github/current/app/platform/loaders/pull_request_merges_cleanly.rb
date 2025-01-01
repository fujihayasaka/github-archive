# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestMergesCleanly < Platform::Loader
      def self.load(pull_id)
        self.for.load(pull_id)
      end

      def self.load_all(pull_ids)
        loader = self.for
        Promise.all(pull_ids.map { |id| loader.load(id) })
      end

      def fetch(pull_ids)
        prs = ::PullRequest.where(id: pull_ids)
          .includes(repository: [:owner, :network])
          .includes(:issue)
          .includes(base_repository: [:owner, :network])
          .includes(head_repository: [:owner, :network])
          .includes(:base_user)
          .includes(:head_user)
          .index_by(&:id)

        prs.reduce({}) do |acc, (id, pull)|
          acc[id] = pull.git_merges_cleanly?
          acc
        end
      end
    end
  end
end
