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
          existing_pull_requests.find(&:open?)
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
      end
    end
  end
end
