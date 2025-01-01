# typed: true
# frozen_string_literal: true

require "test_helper"

module Dependabot
  class PullRequestsServiceTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @dependabot_user = create(:user)
      @repo = create(:repository, owner: @user, from_example: :simple)

      @pull_request = create(:pull_request, :with_mergeable_head, user: @dependabot_user, repository: @repo)
    end

    setup do
      # the user not actually being dependabot doesn't matter much for these tests
      @service = PullRequestsService.new(repository: @repo, dependabot_user: @dependabot_user)
    end

    context "#find_pull_requests" do
      test "finds Dependabot pull requests by number" do
        assert_equal([@pull_request], @service.find_pull_requests(pr_numbers: [@pull_request.number]))
      end

      context "with_commits: true" do
        test "preloads changed commits" do
          GitHub::PrefillAssociations.expects(:prefill_batch_method).with([@pull_request], :prelude_changed_commits).once
          @service.find_pull_requests(pr_numbers: [@pull_request.issue.number], state: nil, with_commits: true)
        end
      end

      context "with state arguments" do
        test "finds Dependabot pull requests with a state" do
          @pull_request.issue.close(@user)
          assert_equal([@pull_request], @service.find_pull_requests(pr_numbers: [@pull_request.number], state: "closed"))
        end
      end
    end

    context "#pr_has_user_commits?" do
      test "is true for non-Dependabot commits without skip flags" do
        oid = create_tree_changes(@repo, parent: @pull_request.head_sha, message: "test", user: @user, files: { "LICENSE" => "MIT" })
        @pull_request.update!(head_sha: oid)

        assert @service.pr_has_user_commits?(pr: @pull_request, include_skipped_commits: false)
      end

      %w[dependabot-skip dependabot_skip skip-dependabot skip_dependabot].each do |skip_flag|
        context "with non-Dependabot commits with [#{skip_flag.gsub("-", "__")}] flag" do
          test "is false when the request ignores skip flags" do
            oid = create_tree_changes(@repo, parent: @pull_request.head_sha, message: "[#{skip_flag}] test", user: @user, files: { "LICENSE" => "MIT" })
            @pull_request.update!(head_sha: oid)

            refute @service.pr_has_user_commits?(pr: @pull_request, include_skipped_commits: false)
          end

          test "is true when the request includes skip flags" do
            oid = create_tree_changes(@repo, parent: @pull_request.head_sha, message: "[#{skip_flag}] test", user: @user, files: { "LICENSE" => "MIT" })
            @pull_request.update!(head_sha: oid)

            assert @service.pr_has_user_commits?(pr: @pull_request, include_skipped_commits: true)
          end
        end
      end
    end

    def create_tree_changes(repo, parent:, message: "", user:, files: [])
      Repositories.domain.commits.create_tree_changes(
        repository: repo,
        parent_oids: [parent],
        info: {
          "message"   => message,
          "committer" => {
            "email"   => user.git_author_email,
            "name"    => user.git_author_name,
            "time"    => user.time_zone.now.iso8601,
          },
        },
        files:
      )
    end
  end
end
