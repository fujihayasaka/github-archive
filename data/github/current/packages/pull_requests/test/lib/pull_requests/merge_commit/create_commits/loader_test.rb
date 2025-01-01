# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module CreateCommits
      class LoaderTest < GitHub::TestCase
        include Enums
        Spokesd.share_spokesdb(self)

        fixtures do
          @owner = create(:user, login: "ari")
          @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
          @forker = create(:user, login: "bwalsh")
          @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

          @pull = PullRequest.create_for(@repo,
            base: "master",
            head: "#{@fork.user}:topic",
            user: @forker,
            issue: create(:issue, user: @forker, repository: @repo))

          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        context "#request" do
          test "it successfully fills a request object with pending commits for a new pull request" do
            # we test if these are nil below, and you can't assert_equality with nil values,
            # so let's make sure they're nil in the PR before we do anything
            assert_nil @pull.mergeable
            assert_nil @pull.merge_commit_sha

            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            fail "expected a Request object, but got a #{request.inspect}" unless request.is_a?(Request)

            assert_equal Enums::Priority::High, request.priority
            assert_equal @pull.id, request.pull_request_id
            assert_equal @pull.base_repository_id, request.base_repository_id
            assert_equal @pull.head_repository_id, request.head_repository_id
            assert_equal @pull.base_sha, request.base_branch_sha
            assert_equal @pull.head_sha, request.head_branch_sha
            assert_equal @pull.conflict.present?, request.database_merge_conflict_record_exists?
            assert_nil request.database_mergeable_value
            assert_nil request.database_merge_commit_sha_value
            assert_instance_of Entity::Commits::Pending, request.merge_commit
            assert_instance_of Entity::Commits::Pending, request.rebase_commit
          end

          test "it returns the correct invalid reason if the PR is merged" do
            Spokesd.enable_spokesd

            @pull.merge(@owner)
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::ClosedOrMerged, request
          end

          test "it returns the correct invalid reason if the PR is closed" do
            @pull.close
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::ClosedOrMerged, request
          end

          test "it returns the correct invalid reason if the PR is missing its base repository" do
            @pull.base_repository_id = nil
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::MissingBaseRepository, request
          end

          test "it returns the correct invalid reason if the PR is missing its head repository" do
            @pull.head_repository_id = nil
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::MissingHeadRepository, request
          end

          test "it returns the correct invalid reason if the PR is missing its base branch sha" do
            @pull.repository.refs.find(@pull.base_ref).delete(@owner)
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::MissingBaseBranchSha, request
          end

          test "it returns the correct invalid reason if the PR is missing its head branch sha" do
            @fork.repository.refs.find(@pull.head_ref).delete(@owner)
            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::MissingHeadBranchSha, request
          end

          test "duplicate requests are skipped" do
            MergeCommitRequest.create!(
              repository_id: @repo.id,
              pull_request_id: @pull.id,
              base_branch_sha: @pull.mergeable_base_sha,
              head_branch_sha: @pull.mergeable_head_sha,
              base_repository_id: @pull.base_repository_id,
              head_repository_id: @pull.head_repository_id,
              priority: Enums::Priority::High.serialize,
              merge_sha: @pull.base_sha,
              merge_state: Enums::CommitState::Created.serialize,
              rebase_sha: @pull.head_sha,
              rebase_state: Enums::CommitState::Created.serialize,
            )

            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            assert_equal InvalidRequestReason::DuplicateRequest, request
          end

          test "the pull request's merge commits are found when present" do
            merge_commit = @repo.commits.create_merge_commit(
              @owner,
              @pull.mergeable_base_sha,
              @pull.mergeable_head_sha,
            ).first
            base_sha, head_sha = merge_commit.parent_oids
            @pull.merge_commit_sha = merge_commit.sha

            rebase_commit_sha = begin
              case result = GitSystems::CreateRebaseCommit.new(
                repository: @repo,
                base_sha:,
                head_sha:,
                name: "tester",
                email: "test@test.com",
                timestamp: Time.current,
                timeout: 7.seconds,
              ).call
              when GitSystems::Commit::Created
                result.sha
              else fail "failed to create rebase commit"
              end
            end

            @repo.refs.create(@pull.rebase_ref, rebase_commit_sha, @owner)

            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            fail "expected a Request object, but got a #{request.inspect}" unless request.is_a?(Request)

            request_merge_commit = request.merge_commit
            fail "expected Entity::Commits::Found, but got a #{request_merge_commit.inspect}" unless request_merge_commit.is_a?(Entity::Commits::Found)
            assert_equal merge_commit.sha, request_merge_commit.sha
            assert_equal base_sha, request_merge_commit.base_sha
            assert_equal head_sha, request_merge_commit.head_sha

            request_rebase_commit = request.rebase_commit
            fail "expected Entity::Commits::Found, but got a #{request_rebase_commit.inspect}" unless request_rebase_commit.is_a?(Entity::Commits::Found)
            assert_equal rebase_commit_sha, request_rebase_commit.sha
          end

          test "when the repository is set to skip rebases" do
            @repo.enable_feature(:merge_commit_request_skip_rebase_via_api)
            @repo.update_merge_settings(@owner, rebase_allowed: false, merge_allowed: false)

            request = Loader.new(pull_request: @pull, repository: @pull.repository).request
            fail "expected a Request object, but got a #{request.inspect}" unless request.is_a?(Request)

            assert_instance_of Entity::Commits::Skipped, request.rebase_commit
          end
        end

        context "#skip_rebase_for?" do
          test "skip_rebase_for? returns true when feature is enabled and neither commit type is allowed" do
            repository = @pull.repository
            repository.enable_feature(:merge_commit_request_skip_rebase_via_api)
            @pull.stubs(:merge_commit_allowed?).returns(false)
            @pull.stubs(:rebase_merge_allowed?).returns(false)

            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            refute loader.include_rebase_commit?
          end

          test "skip_rebase_for? returns false when feature is disabled" do
            repository = @pull.repository
            repository.disable_feature(:merge_commit_request_skip_rebase_via_api)

            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            assert loader.include_rebase_commit?
          end

          test "skip_rebase_for? returns false when merge_commit_allowed? is true" do
            repository = @pull.repository
            repository.enable_feature(:merge_commit_request_skip_rebase_via_api)
            repository.stubs(:merge_commit_allowed?).returns(true)

            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            assert loader.include_rebase_commit?
          end

          test "skip_rebase_for? returns false when rebase_merge_allowed? is true" do
            repository = @pull.repository
            repository.enable_feature(:merge_commit_request_skip_rebase_via_api)
            repository.stubs(:rebase_merge_allowed?).returns(true)

            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            assert loader.include_rebase_commit?
          end
        end

        context "#rebase_timeout" do
          test "returns default timeout when feature flag is disabled" do
            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            GitHub.flipper[:rebase_timeout_1sec].disable
            assert_equal 7, loader.rebase_timeout
          end

          test "returns 1 second timeout when feature flag is enabled" do
            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            GitHub.flipper[:rebase_timeout_1sec].enable
            assert_equal 1, loader.rebase_timeout
          end

          test "returns timeout from environment variable if set" do
            loader = Loader.new(pull_request: @pull, repository: @pull.repository)
            ENV["REBASE_TIMEOUT_SECONDS"] = "10"
            assert_equal 10, loader.rebase_timeout
          ensure
            ENV.delete("REBASE_TIMEOUT_SECONDS")
          end
        end
      end

      class LoaderRepositoryAdvisoryTest < GitHub::TestCase
        include Enums
        Spokesd.share_spokesdb(self)

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

          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        test "it successfully fills a request object with pending commits for a fresh PR for a repository advisory" do
          # we test if these are nil below, and you can't assert_equality with two nil values,
          # so let's make sure they are in the PR before we do anything
          assert_nil @pull.mergeable
          assert_nil @pull.merge_commit_sha

          request = Loader.new(pull_request: @pull, repository: @pull.repository).request
          fail "expected a Request object, but got a #{request.inspect}" unless request.is_a?(Request)

          assert_equal Enums::Priority::High, request.priority
          assert_equal @pull.id, request.pull_request_id
          assert_equal @pull.repository&.parent_advisory_repository&.id, request.base_repository_id
          assert_equal @pull.repository_id, request.head_repository_id
          assert_equal @pull.base_sha, request.base_branch_sha
          assert_equal @pull.head_sha, request.head_branch_sha
          assert_equal @pull.conflict.present?, request.database_merge_conflict_record_exists?
          assert_nil request.database_mergeable_value
          assert_nil request.database_merge_commit_sha_value
          assert_instance_of Entity::Commits::Pending, request.merge_commit
          assert_instance_of Entity::Commits::Pending, request.rebase_commit
        end
      end
    end
  end
end
