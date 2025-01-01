# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionTest < GitHub::TestCase
  include CommitTestHelper

  test "requires a user" do
    assert_raises(ArgumentError) do
      Contribution.new(user: nil)
    end
  end

  test "must be a user" do
    org = create(:organization)

    assert_raises(ArgumentError) do
      Contribution.new(user: org)
    end
  end

  context "#organization_id" do
    test "returns nil" do
      user = stub(user?: true)
      contribution = Contribution.new(user: user, subject: stub)
      assert_nil contribution.organization_id
    end
  end

  context "#user" do
    test "returns the user associated with the contribution" do
      user = create(:user)
      contribution = Contribution.new(user: user)
      assert_equal user, contribution.user
    end
  end

  context "#url" do
    test "returns a string URL to view the contribution on the user's profile" do
      klass = Class.new(Contribution) do
        def self.name
          "NeatContribution"
        end

        def associated_subject
          user
        end

        def occurred_at
          DateTime.new(2013, 2, 20)
        end
      end

      user = create(:user)
      contribution = klass.new(user: user)

      assert_equal "/#{user}?tab=overview&from=2013-02-01&to=2013-02-28", contribution.url
    end
  end

  context "#contributions_count" do
    test "returns 1 by default" do
      user = create(:user)
      contribution = Contribution.new(user: user)
      assert_equal 1, contribution.contributions_count
    end
  end

  context "::first_subject_for" do
    test "return nil by default" do
      assert_nil Contribution.first_subject_for(create(:user))
    end
  end

  context ".clear_caches_for_user" do
    test "clears Contribution::Collector cache" do
      user = create(:user)

      Contribution::Accessor.expects(:clear_cache_for_user).with(user).once
      Contribution.clear_caches_for_user(user)
    end

    test "clears cache when joining a repo as a contributor" do
      repo_owner = create(:user, plan: "silver")
      repo = create(:private_repository, owner: repo_owner)
      user = create(:user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "add_repository_member").once

      repo.add_member(user)
      user.reload
    end

    test "clears cache when leaving a repo as contributor" do
      repo_owner = create(:user, plan: "silver")
      repo = create(:private_repository, owner: repo_owner)
      user = create(:user)
      # Not working, maybe try a non factory repo? *shudders*
      repo.add_member(user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "remove_repository_member").once

      repo.remove_member(user)
    end

    test "clears cache when creating a repo" do
      user = create(:user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "create_repository").once

      create(:repository, owner: user)
    end

    test "clears cache when changing repo visibility" do
      user = create(:user, plan: "silver")
      repo = create(:repository, owner: user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "visibility_repository_orchestration").times(2)
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        repo.toggle_visibility(actor: user) # toggle to private
        assert repo.reload.private?
        repo.toggle_visibility(actor: user) # toggle back to public
        assert repo.reload.public?
      end
    end

    test "clears cache when transferring repo ownership" do
      existing_owner = create(:user)
      new_owner = create(:user)
      repo = create(:repository, owner: existing_owner)

      Contribution.expects(:clear_caches_for_user).with(existing_owner, context: "add_repository_member").once
      Contribution.expects(:clear_caches_for_user).with(new_owner, context: "transfer_repository_orchestration").once

      repo.transfer_ownership_to(new_owner, actor: existing_owner)
    end

    test "clears cache when deleting a repo" do
      user = create(:user)
      repo = create(:repository, owner: user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "create_repository").once

      repo.destroy!
    end

    test "skips clears cache when deleting a repo, if kv is unavailable", skip_enterprise: true do
      user = create(:user)
      repo = create(:repository, owner: user)

      GitHub::KV.any_instance.stubs(:del).raises(GitHub::KV::UnavailableError)

      repo.destroy!
    end

    test "clears cache when creating an issue" do
      user = create(:user)
      repo = create(:repository, owner: user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "create_issue_orchestration").once

      create(:issue, :wait_for_orchestration, user: user, repository: repo)
    end

    test "clears cache when creating a pull request" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)

      Contribution.expects(:clear_caches_for_user).with(user, context: "create_pull_request").once

      create(:pull_request, user: user, issue: issue, head_ref: "cr-line-endings")
    end

    test "clears cache when creating a pull request review" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)
      pr = create(:pull_request, user: user, issue: issue, head_ref: "cr-line-endings")

      Contribution.expects(:clear_caches_for_user).with(user, context: "create_pull_request_review").once

      create(:pull_request_review, user: user, pull_request: pr)
    end

    test "clears cache when joining an org" do
      user = create(:user)
      org = create(:organization)

      if GitHub.flipper[:organization_add_remove_orchestrator].enabled?
        Contribution.expects(:bulk_clear_caches_for_users).with { |users| users.pluck(:id) == [user.id] }.once
      else
        Contribution.expects(:clear_caches_for_user).with(user, context: "add_org_member").once
      end

      org.add_member(user)
    end

    test "clears cache when leaving an org" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)

      expected_context = TestEnv.test_all_features? ? "organization_bulk_remove_members_cleanup_job" : "remove_org_member"
      Contribution.expects(:clear_caches_for_user).with(user, context: expected_context).once

      org.remove_member!(user)
    end

    test "clears cache when creating a commit contribution" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      Contribution.expects(:clear_caches_for_user).with(user, context: "track_push").once

      create_commit(repo: repo, user: user, branch: "master", perform_hydro_jobs: [HydroProfilesOnPushJob, HydroRepositoriesOnPushJob])
    end

    test "clears cache when toggling showing private contrib count" do
      user = create(:user)
      profile_settings = user.profile_settings

      Contribution.expects(:clear_caches_for_user).with(user, context: "toggle_private_contribution_count").twice

      profile_settings.show_private_contribution_count = false
      profile_settings.show_private_contribution_count = true
    end

    test "clears cache when contributions are cleared for a user on enterprise" do
      user = create(:user)
      installation = create(:enterprise_installation)

      Contribution.expects(:clear_caches_for_user).with(user, context: "clear_enterprise_user_contributions").once

      EnterpriseContribution.clear_user_contributions!(user, installation.id)
    end

    test "clears cache in enterprise installations when contributions are deleted" do
      user1 = create(:user)
      user2 = create(:user)
      installation = create(:enterprise_installation)
      create(:enterprise_contribution, enterprise_installation: installation, user: user1)
      create(:enterprise_contribution, enterprise_installation: installation, user: user2)

      Contribution.expects(:clear_caches_for_user).with(user1, context: "clear_enterprise_installation_contributions")
      Contribution.expects(:clear_caches_for_user).with(user2, context: "clear_enterprise_installation_contributions")

      EnterpriseContribution.clear_installation_contributions!(installation.id)
    end

    test "clears cache when user is added to a team" do
      user = create(:user)
      org = create(:organization)
      team = create(:team, organization: org)
      org.add_member(user)

      if GitHub.flipper[:use_team_add_member_bulk_method].enabled?
        clear_caches_for_user = :bulk_clear_caches_for_users
        with_user = [user]
        expected_context = "bulk_add_org_team_members"
      else
        clear_caches_for_user = :clear_caches_for_user
        with_user = user
        expected_context = "add_org_team_member"
      end

      Contribution.expects(clear_caches_for_user).with(with_user, context: expected_context)

      team.add_member(user)
    end

    test "clears cache when user is removed from a team" do
      user = create(:user)
      team = create(:team)
      team.add_member(user)

      Contribution.expects(:clear_caches_for_user).with(user, context: "remove_org_team_member")

      team.remove_member(user)
    end
  end
end
