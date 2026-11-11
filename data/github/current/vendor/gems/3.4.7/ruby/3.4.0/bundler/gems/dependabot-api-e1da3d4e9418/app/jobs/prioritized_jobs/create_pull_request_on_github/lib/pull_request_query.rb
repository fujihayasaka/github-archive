# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    module Lib
      class PullRequestQuery
        def initialize(update_job:, updated_dependencies:)
          @update_job = update_job
          @updated_dependencies = updated_dependencies
        end

        def existing_pull_request
          if consider_open_pull_requests_only?
            existing_pull_requests.find(&:open?)
          else
            # Can't just check :merged since we have a data problem and it may have been merged, and then closed.
            resolved, unresolved = existing_pull_requests.partition { |pr| pr.in_state?(:merged, :closed) }
            return unresolved.first if unresolved.any?

            # To prevent excessive queries, only check closed PRs to see if they have ever been merged.
            resolved.find do |pr|
              pr.in_state?(:closed) && pr.pull_request_transitions.where(to_state: "merged").none?
            end
          end
        end

        def existing_pull_requests
          @existing_pull_requests ||=
            if @updated_dependencies.count == 1 &&
               @updated_dependencies.first.previous_version
              single_dependency_prs_for_same_version
            elsif @updated_dependencies.count == 1
              single_dependency_prs_for_same_requirements
            elsif @updated_dependencies.any?(&:previous_version)
              multi_dependency_prs_for_same_version
            else
              multi_dependency_prs_for_same_requirements
            end
        end

        def update_config_pull_requests
          @update_job.update_config.pull_requests.includes(:pull_request_transitions)
        end

        def single_dependency_prs_for_same_version
          update_config_pull_requests.
            where(multiple_dependencies: false).
            joins(:updated_dependencies).
            where(updated_dependencies: {
                    name: @updated_dependencies.first.name,
                    version: @updated_dependencies.first.version,
                    directory: @updated_dependencies.first.directory,
                  })
        end

        def single_dependency_prs_for_same_requirements
          update_config_pull_requests.
            where(multiple_dependencies: false).
            joins(:updated_dependencies).
            where(updated_dependencies: {
                    name: @updated_dependencies.first.name,
                    directory: @updated_dependencies.first.directory,
                  }).
            select do |pr|
              pr.updated_dependencies.first.requirements.map(&:symbolize_keys) ==
                @updated_dependencies.first.requirements
            end
        end

        def multi_dependency_prs_for_same_version
          updated_dependency_set =
            @updated_dependencies.
            to_set { |dep| { "name" => dep.name, "version" => dep.version, "directory" => dep.directory } }
          update_config_pull_requests.
            where(multiple_dependencies: true).select do |pr|
              updated_dependency_set ==
                pr.updated_dependencies.
                to_set { |dep| { "name" => dep.name, "version" => dep.version, "directory" => dep.directory } }
            end
        end

        def multi_dependency_prs_for_same_requirements
          updated_dependency_set =
            @updated_dependencies.
            to_set { |dep| { "name" => dep.name, "requirements" => dep.requirements, "directory" => dep.directory } }
          update_config_pull_requests.
            where(multiple_dependencies: true).select do |pr|
              updated_dependency_set ==
                pr.updated_dependencies.
                to_set { |d| { "name" => d.name, "requirements" => d.requirements, "directory" => d.directory } }
            end
        end

        private

        def consider_open_pull_requests_only?
          @update_job.repo.config_feature_enabled?(:ignore_closed_prs) || @update_job.multi_ecosystem_config_id.present?
        end
      end
    end
  end
end
