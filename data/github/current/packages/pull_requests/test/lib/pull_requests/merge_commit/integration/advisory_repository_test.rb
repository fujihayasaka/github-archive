# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module Integration
      class AdvisoryRepositoryTest < GitHub::TestCase
        Spokesd.share_spokesdb(self)

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
        end

        test "generates merge commits for advisory repositories" do
          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)

          # Should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          # Run the CPRMC process.
          result = Service.new(repository: @pull.repository).call

          # All requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @pull.repository.id).count

          # PR should be mergeable.
          assert PullRequest.find(@pull.id).currently_mergeable?
        end
      end
    end
  end
end
