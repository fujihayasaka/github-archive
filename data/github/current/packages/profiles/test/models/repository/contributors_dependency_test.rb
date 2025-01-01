# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryContributorsDependencyTest < GitHub::TestCase
  fixtures do
    @bot      = create(:bot)
    @mojombo  = create(:user, login: "mojombo2", plan: "medium", email: "tom@mojombo.com")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium", email: "chris@ozmm.org")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @grit     = create(:repository, name: "grit",     owner: @mojombo, from_example: :mojombo_grit)
  end

  setup do
    @grit.update_default_branch("master")
  end

  context "#contributors" do
    test "can include contributors with private profiles" do
      @defunkt.update!(private_profile: true)

      contributors = @grit.contributors(with_anon: false, skip_private_profiles: false)

      assert_predicate contributors, :computed?
      assert_same_elements [@defunkt, @mojombo], contributors.value.map { |user, _count| user }
    end

    test "can skip contributors with private profiles" do
      @defunkt.update!(private_profile: true)

      contributors = @grit.contributors(with_anon: false, skip_private_profiles: true)

      assert_predicate contributors, :computed?
      assert_equal [@mojombo], contributors.value.map { |user, _count| user }
    end
  end

  context "#top_contributors" do
    test "returns contributors to the repository ordered by commit count then commit date" do
      create(:commit_contribution, :with_summaries, repository: @grit, user: @mojombo, commit_count: 1,
        committed_date: Date.current - 2.days)
      create(:commit_contribution, :with_summaries, repository: @grit, user: @defunkt, commit_count: 2,
        committed_date: Date.current - 1.day)
      create(:commit_contribution, :with_summaries, repository: @grit, user: @pj, commit_count: 3,
        committed_date: Date.current)
      create(:commit_contribution, :with_summaries, repository: @grit, user: @bot, commit_count: 4,
        committed_date: 1.day.ago)
      contributors = @grit.top_contributors(limit: 4, viewer: nil)

      assert_equal [@bot, @pj, @defunkt, @mojombo], contributors,
        "should have contributor with most commits first, then by oldest contributor"
    end

    test "can skip bots" do
      contributors = @grit.top_contributors(limit: 4, viewer: nil, skip_bots: true)

      refute_includes contributors, @bot, "should have skipped bot contributors"
    end

    test "can skip the viewer" do
      contributors = @grit.top_contributors(limit: 4, viewer: @defunkt, skip_viewer: true)

      refute_includes contributors, @defunkt, "should have skipped the viewer"
    end

    test "can include contributors with private profiles" do
      create(:commit_contribution, :with_summaries, repository: @grit, user: @pj, commit_count: 3,
        committed_date: Date.current)
      @pj.update!(private_profile: true)

      contributors = @grit.top_contributors(limit: 4, viewer: @defunkt, skip_private_profiles: false)

      assert_includes contributors, @pj, "should have included the private profile contributor"
    end

    test "can skip contributors with private profiles" do
      @pj.update!(private_profile: true)

      contributors = @grit.top_contributors(limit: 4, viewer: @defunkt, skip_private_profiles: true)

      refute_includes contributors, @pj, "should have skipped the private profile contributor"
    end

    test "sets limit to 0 and logs when limit is < 0" do
      GitHub.logger.expects(:warn).with("limit param out of range -1",
                                        "code.namespace": "Repository",
                                        "code.function": :top_contributors)

      contributors = @grit.top_contributors(limit: -1, viewer: @defunkt)

      assert_empty contributors
    end

    test "does not raise on very large limit" do
      create(:commit_contribution, :with_summaries, repository: @grit, user: @mojombo, commit_count: 1)

      contributors = @grit.top_contributors(limit: "99999999999999999999".to_i, viewer: @defunkt)

      assert_equal 1, contributors.count
    end
  end

  context "#show_first_time_contributor_banner?" do
    context "not in enterprise", skip_enterprise: true do
      test "returns true if the user has no contributions to the repository" do
        assert @grit.show_first_time_contributor_banner?(user: @defunkt)
      end

      test "returns false if the repository owner is spammy", skip_enterprise: true do
        spammy_user = create(:user, spammy: true)
        repo = create(:repository, owner: spammy_user)
        repo.add_member(@defunkt)

        refute repo.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show for spammy repo"
      end

      test "returns false if the user is blocked by the repository owner", skip_enterprise: true do
        @mojombo.block(@defunkt, actor: @mojombo)
        @grit.reload
        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show for blocked users"
      end

      test "returns false if the viewer is the repo owner" do
        refute @grit.show_first_time_contributor_banner?(user: @mojombo), "Expected FTC banner not to show for repo owner"
      end

      test "returns false if the viewer has any contributions to the viewed repo" do
        create(:commit_contribution, :with_summaries, user: @defunkt, repository: @grit)

        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Exprected FTC banner not to show if viewer has > 0 contributions to the repo"
      end

      test "returns false if the user has already dismissed the banner for the repository", skip_enterprise: true do
        @defunkt.dismiss_repository_notice("first_time_contributor_issues_banner", repository_id: @grit.id)
        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show after user has dismissed"
      end

      test "returns false if the user has already dismissed the banner for all repositories", skip_enterprise: true do
        @defunkt.dismiss_notice("first_time_contributor_issues_banner")
        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show after user has dismissed"
      end

      test "returns false if the viewer is not an authenticated user", skip_enterprise: true do
        refute @grit.show_first_time_contributor_banner?(user: nil), "Expected FTC banner not to show for unauthenticated user"
      end

      test "return false if the repo is not writable", skip_enterprise: true do
        @grit.set_archived

        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show if repo is not writable"
      end

      test "returns false if the repo is private", skip_enterprise: true do
        private_repo = create(:private_repository, owner: @mojombo)

        refute private_repo.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show if repo is private"
      end

      test "returns false if the repo is a fork", skip_enterprise: true do
        forked = create(:fork_repository, forker: @pj, fork_repo: @grit)

        refute forked.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show if repo is a fork"
      end

      test "returns false with emu and repo is not enterprise managed", skip_enterprise: true do
        emu = create(:emu)

        refute @grit.show_first_time_contributor_banner?(user: emu, owner_managed: false), "Expected FTC banner not to show for emu if repo is not managed"
      end

      test "returns true with emu and repo is enterprise managed", skip_enterprise: true do
        emu = create(:emu)

        assert @grit.show_first_time_contributor_banner?(user: emu, owner_managed: true)
      end
    end

    context "in enterprise", enterprise_only: true do
      test "returns false in the GHE environment" do
        refute @grit.show_first_time_contributor_banner?(user: @defunkt), "Expected FTC banner not to show in GHE environment"
      end
    end
  end
end
