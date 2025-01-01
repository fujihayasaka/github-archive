# typed: strict
# frozen_string_literal: true

module Checks
  class Domain
    class CheckSuites < GH::Domain::Base
      # Find or create a check suite for the given repository and head SHA.
      #
      # @param repo The Repository in which to create the check suite.
      # @param head_sha The head SHA to scope to.
      # @param github_app_id The GitHub App ID creating the check suite.
      # @return The existing CheckSuite if it exists, or a new CheckSuite if it does not.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(repo: Repository, head_sha: String, github_app_id: Integer).
        returns(CheckSuite).
        checked(:always).
        on_failure(:raise)
      end
      def find_or_create(repo:, head_sha:, github_app_id:)
        attrs = {
          head_sha: head_sha,
          github_app_id: github_app_id,
        }

        check_suite = repo.check_suites.find_by(attrs)
        return check_suite if check_suite.present?

        # When creating check suites elsewhere in the app, if the push is known we use it to set the
        # head_branch attribute. While we don't accept a head_branch param from integrators in the
        # api, it seems reasonable to use the information we know to better fill in the details.
        push = Repositories.domain.pushes.by_repo_id_and_after(after: head_sha, repository_id: repo.id)

        attrs.merge!(
          head_branch: push&.branch_name,
          push_id: push&.id,
        )

        # Attempts to find the check suite, otherwise tries to create the check suite.
        # If creation fails because the record is not unique, retry up to 3 times.
        retries = 3
        begin
          repo.check_suites.find_by(attrs) || repo.check_suites.create!(attrs)
        rescue ActiveRecord::RecordNotUnique
          GitHub.dogstats.increment("checks.check_suite_uniqueness_collision")
          (retries -= 1) && retry if retries > 0
          raise # Re-raises the same error
        end
      end
    end
  end
end
