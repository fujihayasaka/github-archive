# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module Integration
      class AdvisoryRepositoryTest < GitHub::TestCase
        # Borrowed heavily from:
        # https://github.com/github/github/blob/0866568b509349d1ce21984c5d703741a10171b4/packages/security_products/test/models/repository_advisory_test.rb#L1636
        fixtures do
          @admin = create(:paid_user)
          @org   = create(:business_organization, login: "acme", admin: @admin)
          @repo  = create(:repository, name: "public-test", owner: @org, from_example: :pull_request_source)
          @team  = create(:team, organization: @org)

          @author = create(:user, login: "author")
          @publisher = create(:user, login: "publisher")
          @collab = create(:user, login: "collab")
          @rando = create(:user, login: "Random-user")

          @integration = create :integration
          @installation = make_integration_installation integration: @integration, target: @repo.owner, permissions: { "repository_advisories" => :write }

          description = <<~MD
            **Urgent**: Vulnerability has been _disclosed_ 😱

            [Read more here](https://example.com/oh-noes)
          MD

          @advisory = create(:repository_advisory,
                              repository: @repo,
                              author: @author,
                              title: "💎 Path Traversal on Default Installed Rails Application",
                              description: description,
                              cve_id: "CVE-1900-0001",
                              severity: "moderate",
                              created_at: 1.minute.ago)

          @advisory.affected_products.first.update!(
            package: "my-example-package.rb",
            ecosystem: "RubyGems",
            affected_versions: "<5.1.0",
            patches: "No patches currently available.",
          )

          GitHub.context.push(actor_id: @admin.id)
          @advisory_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @admin)
          @advisory_repo.save!
          example_repo :pull_request_fork, @advisory_repo

          @pull = create :pull_request,
            issue: create(:issue, repository: @advisory_repo, user: @admin),
            base_repository: @advisory.repository,
            head_repository: @advisory_repo,
            base_ref: "master-forward-2",
            head_ref: "topic"

          make_trusted_oauth_apps_owner
          @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)

          disable_feature_flag(:disable_merge_commit_create_commits_jobs)

          # Internal FF to fetch_workspace_base_ref!
          disable_feature_flag(:disable_xnetwork_fetch)

          # Enable the fix for advisory workspaces.
          enable_feature_flag(:cprmc_fetch_workspace_base_ref)

          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        test "generates merge commits for advisory repositories" do
          # Should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          generate_merge_commits(@pull)

          # PR should be mergeable.
          assert PullRequest.find(@pull.id).currently_mergeable?
        end

        test "can resolve the correct base sha when the target repo has had a push" do
          # Should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          # Create a new commit in the target branch.
          commit = @repo.commits.create({ message: "Add file", author: @admin }) do |files|
            files.add "file1.txt", "content"
          end

          @repo.refs[@pull.base_ref].update(commit, @admin)

          generate_merge_commits(@pull)

          assert PullRequest.find(@pull.id).currently_mergeable?
        end

        private

        def generate_merge_commits(pull)
          perform_enqueued_jobs only: [CreateMergeCommitsJob, BatchRefUpdatesJob] do
            # TODO: Swap this to the public interface.
            CreateMergeCommitsJob.perform_later(pull)
          end
        end
      end
    end
  end
end
