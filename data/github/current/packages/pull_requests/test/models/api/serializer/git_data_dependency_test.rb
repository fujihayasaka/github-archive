# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class GitDataTest < Api::SerializerTestCase
  fixtures do
    org = create(:organization)
    @user = create(:user)
    @team = create(:team, organization: org)
    @app = create(:integration)

    @repo = create(:repository, owner: org, from_example: :review_comment_fork)
    org.add_member(@user)
    @repo.add_member(@user)
    @repo.add_team(@team, action: :write)
    @app_installation = make_integration_installation(
      integration: @app,
      repository: @repo,
      permissions: { "contents" => :write },
    )


    create(:protected_branch, repository: @repo, name: "high_line_number_change")
    branch = create(:protected_branch,
      repository: @repo,
      name: "master",
      admin_enforced: true,
      required_status_checks_enforcement_level: :non_admins,
      pull_request_reviews_enforcement_level: :non_admins,
      signature_requirement_enforcement_level: :non_admins,
      strict_required_status_checks_policy: true,
      dismiss_stale_reviews_on_push: true,
      require_code_owner_review: true,
      required_approving_review_count: 3,
      required_review_thread_resolution_enforcement_level: :non_admins,
    )
    branch.update_restrictions(users: [@user.login], teams: [@team.slug], integrations: [@app.slug], entry_point: :test_case)
    branch.replace_dismissal_restricted_actors(user_ids: [@user.id], team_ids: [@team.id], integration_ids: [@app.id])
    branch.create_required_status_checks(["foo-test"])
  end

  context "#protected_branch_hash" do
    test "conforms to the JSON schema" do
      ref = @repo.heads.find("high_line_number_change")
      output = serialize_hash_method(:protected_branch_hash, ref)
    end

    test "with a fully enabled protected branch contains expected data" do
      ref = @repo.heads.find("master")
      output = serialize_hash_method(:protected_branch_hash, ref)

      assert_equal true, output["enforce_admins"]["enabled"]
      assert_equal true, output["required_status_checks"]["strict"]
      assert_equal ["foo-test"], output["required_status_checks"]["contexts"]
      assert_equal 1, output["restrictions"]["users"].count
      assert_equal 1, output["restrictions"]["teams"].count
      assert_equal 1, output["restrictions"]["apps"].count
      assert_equal @user.login, output["restrictions"]["users"].first["login"]
      assert_equal @team.name, output["restrictions"]["teams"].first["name"]
      assert_equal @app.name, output["restrictions"]["apps"].first["name"]
      assert_equal true, output["required_pull_request_reviews"]["dismiss_stale_reviews"]
      assert_equal true, output["required_pull_request_reviews"]["require_code_owner_reviews"]
      assert_equal @user.login, output["required_pull_request_reviews"]["dismissal_restrictions"]["users"].first["login"]
      assert_equal @team.name, output["required_pull_request_reviews"]["dismissal_restrictions"]["teams"].first["name"]
      assert_equal @app.name, output["required_pull_request_reviews"]["dismissal_restrictions"]["apps"].first["name"]
      assert_equal 3, output["required_pull_request_reviews"]["required_approving_review_count"]
      assert_equal true, output["required_signatures"]["enabled"]
      assert_equal false, output["allow_force_pushes"]["enabled"]
      assert_equal false, output["allow_deletions"]["enabled"]
      assert_equal true, output["required_conversation_resolution"]["enabled"]
    end
  end

  context "#protected_branch_required_status_checks_hash" do
    test "payload is valid" do
      ref = @repo.heads.find("master")
      output = serialize_hash_method(:protected_branch_required_status_checks_hash, ref)

      assert_equal true, output["strict"]
      assert_equal ["foo-test"], output["contexts"]
    end
  end

  context "#protected_branch_required_signatures_hash" do
    test "payload is valid" do
      ref = @repo.heads.find("master")
      output = serialize_hash_method(:protected_branch_required_signatures_hash, ref)

      assert_equal true, output["enabled"]
    end
  end

  context "#git_commit_hash" do

    test "payload is valid" do
      commit = @repo.commits.find("a11d2cbabdc03d2d98914329dca9fb43a80ae0b0")
      create(:commit_comment, commit_id: commit.oid, repository: commit.repository)
      user = create(:user, email: "mclark@github.com")

      output = serialize_hash_method(:git_commit_hash, commit)

      author_info = {
        "name" => commit.author_name,
        "email" => commit.author_email,
        "date" => commit.authored_date,
      }
      committer_info = {
        "name" => commit.committer_name,
        "email" => commit.committer_email,
        "date" => commit.committed_date,
      }

      assert_equal commit.oid, output["sha"]
      assert_equal commit.global_relay_id, output["node_id"]
      assert_equal author_info, output["commit"]["author"]
      assert_equal committer_info, output["commit"]["committer"]
      assert_equal commit.message, output["commit"]["message"]
      assert_equal commit.tree_oid, output["commit"]["tree"]["sha"]
      assert_equal 1, output["commit"]["comment_count"]
      assert_equal user.id, output["author"]["id"]
      assert_equal user.id, output["committer"]["id"]
      assert_equal commit.parent_oids, output["parents"].map { |p| p["sha"] }
    end

    test "loaded options" do
      commit = @repo.commits.find("a11d2cbabdc03d2d98914329dca9fb43a80ae0b0")
      create(:commit_comment, commit_id: commit.oid, repository: commit.repository)

      user = create(:user)
      emails = { "mclark@github.com" => user }
      counts = { commit.oid => 12 }

      output = serialize_hash_method(:git_commit_hash, commit, { repo: commit.repository, emails: emails, comment_counts: counts, diff: commit.init_diff })

      assert_equal 12, output["commit"]["comment_count"]
      assert_equal user.id, output["author"]["id"]
      assert_equal user.id, output["committer"]["id"]

      stats = {
        "additions" => 10,
        "deletions" => 3,
        "total" => 13,
      }

      assert_equal stats, output["stats"]
      assert_equal 1, output["files"].count
      assert_equal "aquaman2.txt", output["files"].first["filename"]
    end

    test "returns nil when commit is nil" do
      assert_nil serialize_hash_method(:git_commit_hash, nil)
    end

    test "lists multiple parents" do
      # make it a merge commit to test multiple parents
      merge_commit, _ = @repo.commits.create_merge_commit(@repo.owner, @repo.heads.find("master").target_oid,
        @repo.heads.find("topic").target_oid)

      output = serialize_hash_method(:git_commit_hash, merge_commit)

      parents = output["parents"]
      assert_equal merge_commit.parent_oids, parents.map { |p| p["sha"] }
    end
  end

  context "#branch_with_protection_hash" do
    context "with an unprotected ref" do
      test "payload is valid" do
        ref = @repo.heads.find("blob_position_shift")

        output = serialize_hash_method(:branch_with_protection_hash, ref)

        assert_equal false, output["protected"]
        assert_equal false, output["protection"]["enabled"]
        expected_status_checks = {
          "enforcement_level" => "off",
          "contexts" => [],
          "checks" => [],
        }
        assert_equal expected_status_checks, output["protection"]["required_status_checks"]
      end
    end

    context "with a protected ref" do
      test "payload is valid" do
        protected_branch = create(:protected_branch, repository: @repo, name: "blob_position_shift", required_status_checks_enforcement_level: :non_admins)
        protected_branch.create_required_status_checks(["test-context"])
        ref = @repo.heads.find("blob_position_shift")

        output = serialize_hash_method(:branch_with_protection_hash, ref)

        assert_equal true, output["protected"]
        assert_equal true, output["protection"]["enabled"]

        expected_status_checks = {
          "enforcement_level" => "non_admins",
          "contexts" => ["test-context"],
          "checks" => [
            { "context" => "test-context", "app_id" => nil },
          ],
        }

        assert_equal expected_status_checks, output["protection"]["required_status_checks"]
      end
    end
  end

  context "associated_pull_requests_hash" do
    test "payload is valid for PR from a forked repo" do
      repo = create(:repository, owner: @user, from_example: :pull_request_source)
      forker = create(:user)
      fork = create(:fork_repository, forker: forker, fork_repo: repo, from_example: :pull_request_fork)

      pull_request = create(:pull_request,
        issue: create(:issue, repository: repo),
        base_repository: repo,
        base_user: @user,
        base_ref: "master",
        head_repository: fork,
        head_user: forker,
        head_ref: "topic",
      )

      ref = repo.heads.find("topic")
      commit = fork.heads.find("topic").commit
      output = serialize_hash_method(:associated_pull_requests_hash, commit, { repo: fork })
      assert_equal output[0]["id"], pull_request.id
    end
  end
end

class GitDataEnterpriseManagedTest < Api::SerializerTestCase
  fixtures do
    @emu = create :emu
    @business = @emu.enterprise_managed_business
    @org = create :organization, business: @business
    @org.add_member(@emu)

    @org_repo = create :repository, owner: @org, from_example: :commit_comments
    @user_repo = create :repository, owner: @emu, from_example: :commit_comments

  end

  setup do
    @org_repo_commit = create :commit, repository: @org_repo, committer: @emu
    @user_repo_commit = create :commit, repository: @user_repo, committer: @emu
  end

  context "#git_commit_hash" do
    test "org owned repo returns EMU user as author and committer" do
      output = serialize_hash_method(:git_commit_hash, @org_repo_commit)

      assert_equal output["author"]["id"], @emu.id
      assert_equal output["author"]["login"], @emu.login

      assert_equal output["committer"]["id"], @emu.id
      assert_equal output["committer"]["login"], @emu.login
    end

    test "org owned repo returns EMU user when normal GitHub user exists and primary email is EMU profile email" do
      create :user, email: @emu.profile_email

      output = serialize_hash_method(:git_commit_hash, @org_repo_commit)

      assert_equal output["author"]["id"], @emu.id
      assert_equal output["author"]["login"], @emu.login

      assert_equal output["committer"]["id"], @emu.id
      assert_equal output["committer"]["login"], @emu.login
    end

    test "user owned repo returns EMU user as author and committer" do
      output = serialize_hash_method(:git_commit_hash, @user_repo_commit)

      assert_equal output["author"]["id"], @emu.id
      assert_equal output["author"]["login"], @emu.login

      assert_equal output["committer"]["id"], @emu.id
      assert_equal output["committer"]["login"], @emu.login
    end

    test "user owned repo returns EMU user when normal GitHub user exists and primary email is EMU profile email" do
      create :user, email: @emu.profile_email

      output = serialize_hash_method(:git_commit_hash, @user_repo_commit)

      assert_equal output["author"]["id"], @emu.id
      assert_equal output["author"]["login"], @emu.login

      assert_equal output["committer"]["id"], @emu.id
      assert_equal output["committer"]["login"], @emu.login
    end
  end
end unless GitHub.single_business_environment?
