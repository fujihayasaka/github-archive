# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module StatusChecks
      class LoaderTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "wiseguy")

          @org = create(:organization, plan: "business_plus")
          @org.add_member @owner, action: :write
          @repo = create(:private_repository, owner: @org, name: "source", from_example: :review_comment_fork)
          branch_attributes = {
            name: "master",
            creator: @owner,
            required_status_checks_enforcement_level: :non_admins,
          }
          @protected_branch = @repo.protected_branches.create(branch_attributes)
          @status_check = RequiredStatusCheck.new(
            protected_branch: @protected_branch,
            context: "Testing",
          )
          @status_check.save!

          @pull = create(:pull_request,
              repository: @repo,
              base_repository: @repo,
              base_user: @repo.owner,
              base_ref: "master",
              head_repository: @repo,
              head_user: @repo.owner,
              head_ref: "topic",
              user: @owner
            )

          @actions_app = create :launch_integration
          # status context
          @oauth_application = create(:oauth_application, name: "Lofty-CI", url: "https://lofty-ci.com/")
          @status_context = create(:status,
            oauth_application: @oauth_application,
            repository: @repo,
            creator: @repo.owner,
            sha: @pull.head_sha,
            context: "context1",
            state: "success",
            description: "yeah",
            target_url: "https://github.com/"
          )

          # check run
          @github_app = create :integration, default_permissions: { "checks" => :write }
          @check_suite = create(:check_suite, repository: @repo, github_app: @github_app, head_sha: @pull.head_sha)
          @check_run = create(:check_run, name: "foo", check_suite: @check_suite, status: :completed, completed_at: Time.now, conclusion: :success)
        end

        test "loads everything that the payload class needs" do
          status_checks = PullRequests::PageData::StatusChecks::Loader.load(
            repository: @repo,
            pull_request: @pull,
            avatar_size: 40,
          )

          fail "Expected status checks to be loaded" if status_checks.nil?

          payload, queries = log_cleaned_queries do
            PullRequests::PageData::StatusChecksSerializer.new(
              status_checks:,
              pull_request: @pull,
              avatar_size: nil
            ).to_hash
          end

          # The number of checks is largely incidental, but this assertion
          # gives us confidence that all of the expected data was loaded.
          assert_equal 3, payload["statusChecks"].length

          # TODO: This should be zero, but currently the
          # `Payload#workflows_pending_approval?` method makes an additional
          # query.
          expected_query_count = 1

          assert_equal(
            expected_query_count, queries.count,
            "Expected #{expected_query_count} queries, got #{queries.count}:\n\n"\
            "#{queries.map { _1.digested_sql + "\n\n  " + _1.backtrace.join("\n  ") }.join("\n\n")}"
          )
        end
      end
    end
  end
end
