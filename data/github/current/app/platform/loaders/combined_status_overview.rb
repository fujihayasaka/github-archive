# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CombinedStatusOverview < Platform::Loader
      include Scientist

      def self.load(repository, sha)
        self.for(repository).load(sha)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(oids)
        bindings = { head_shas: oids, repository_id: @repository.id }

        hash_results = Checks.domain.check_runs.summaries_for_shas(oids, repository_id: @repository.id)

        statuses = ::Statuses.domain.current_statuses_for_shas(repository_id: @repository.id, shas: oids)

        hash_results += statuses.map do |status|
          {}.tap do |h|
            h["total"] = 1
            h["conclusion"] = status.state
            h["sha"] = status.sha
          end
        end

        records_by_sha = hash_results.group_by { |result| result["sha"] }

        records_by_sha.default = [default]
        records_by_sha
      end

      def default
        {}.tap do |h|
          h["total"] = 0
          h["conclusion"] = nil
        end
      end

      def self.short_text(rows)
        total_count = rows.inject(0) { |sum, x| sum + x["total"] }
        return nil if total_count == 0

        successful_count = rows.inject(0) { |sum, x| sum + (x["conclusion"] == "success" ? x["total"] : 0) }
        "#{successful_count} / #{total_count} checks OK"
      end
    end
  end
end
