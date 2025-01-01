# typed: true
# frozen_string_literal: true

require "test_helper"

class CommunityProfileTest < GitHub::TestCase

  setup do
    @repo_with_community_files = create(:repository, from_example: :community_files_with_legacy_issue_template)
    @repo_with_empty_template = create(:repository, from_example: :empty_community_files)
    @repo_with_blank_coc = create(:repository, from_example: :code_of_conduct_blank)
    @repo_with_flippant_coc = create(:repository, from_example: :code_of_conduct_flippant)
    @repo_with_unconventional_coc = create(:repository, from_example: :code_of_conduct_other)
    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)
    @dot_github_repo = create(:repository, owner: @org, name: ".github", from_example: :community_files)

  end

  context "#health_percentage" do
    if GitHub.can_report?
      context "when tiered_reporting is included" do
        test "three measures should be 37" do
          @repo_with_empty_template.update_attribute(:owner, (create :organization))
          # These are stubbed out for now since the original test was just checking math the other
          # tests in this ensure we actually check the files and methods
          profile = CommunityProfile.create(repository: @repo_with_empty_template)
          profile.stubs(:sufficient_code_of_conduct?).returns(true)
          profile.stubs(:contributing?).returns(true)
          profile.stubs(:readme?).returns(true)

          assert_equal 37, profile.health_percentage # 3 out of 8 measures
        end

        test "with just files should be 75" do
          @repo_with_community_files.update_attribute(:owner, @org)
          profile = CommunityProfile.create(repository: @repo_with_community_files)

          assert_equal 75, profile.health_percentage # 6 out of 8 measures
        end

        test "with all measures should be 100" do
          @repo_with_community_files.update_attribute(:owner, @org)
          @repo_with_community_files.update_attribute(:description, "hack the planet")
          @repo_with_community_files.enable_tiered_reporting(actor: @org.admin)

          profile = CommunityProfile.create(repository: @repo_with_community_files)
          assert_equal 100, profile.health_percentage # 7 out of 7 or 8 out of 8 measures
        end
      end
    end

    context "when tiered reporting is not included" do
      test "three measures should be 42" do
        refute_predicate @repo_with_empty_template, :eligible_for_tiered_reporting?
        # These are stubbed out for now since the original test was just checking math the other
        # tests in this ensure we actually check the files and methods
        profile = CommunityProfile.create(repository: @repo_with_empty_template)
        profile.stubs(:sufficient_code_of_conduct?).returns(true)
        profile.stubs(:contributing?).returns(true)
        profile.stubs(:readme?).returns(true)

        assert_equal 42, profile.health_percentage # 3 out of 7 measures
      end

      test "with just files should be 85" do
        refute_predicate @repo_with_community_files, :eligible_for_tiered_reporting?
        profile = CommunityProfile.create(repository: @repo_with_community_files)

        assert_equal 85, profile.health_percentage # 6 out of 7 measures
      end

      test "with all measures should be 100" do
        refute_predicate @repo_with_community_files, :eligible_for_tiered_reporting?
        @repo_with_community_files.update_attribute(:description, "hack the planet")
        profile = CommunityProfile.create(repository: @repo_with_community_files)

        assert_equal 100, profile.health_percentage # 7 out of 7 or 6 out of 6 measures
      end
    end

    test "no measures should be 0" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      assert_equal 0, profile.health_percentage
    end
  end

  context ".health_metrics" do
    if GitHub.can_report?
      test "returns full list when repo is org-owned" do
        expected_metrics =
          [
            :sufficient_code_of_conduct?,
            :contributing?,
            :license?,
            :readme?,
            :description?,
            :pr_or_issue_template?,
            :security_policy?,
            :tiered_reporting_enabled?,
          ]

        profile = CommunityProfile.create(repository: @org_repo)
        assert_equal expected_metrics, profile.health_metrics
      end

      context "returns list without tiered reporting" do
        test "when org is owned by a user" do
          expected_metrics =
            [
              :sufficient_code_of_conduct?,
              :contributing?,
              :license?,
              :readme?,
              :description?,
              :pr_or_issue_template?,
              :security_policy?,
            ]

          profile = CommunityProfile.create(repository: @repo_with_empty_template)
          assert_equal expected_metrics, profile.health_metrics
        end

        test "when profile.repo is nil" do
          expected_metrics =
            [
              :sufficient_code_of_conduct?,
              :contributing?,
              :license?,
              :readme?,
              :description?,
              :pr_or_issue_template?,
              :security_policy?,
            ]

          profile = CommunityProfile.create(repository: @org_repo)
          profile.expects(:repository).returns(nil)
          assert_equal expected_metrics, profile.health_metrics
        end
      end
    else
      test "returns list without tiered reporting when on enterprise" do
        expected_metrics =
          [
            :sufficient_code_of_conduct?,
            :contributing?,
            :license?,
            :readme?,
            :description?,
            :pr_or_issue_template?,
            :security_policy?,
          ]

        profile = CommunityProfile.create(repository: @org_repo)
        assert_equal expected_metrics, profile.health_metrics
      end
    end
  end

  context "CommunityProfile#issue_template" do
    test "returns legacy issue template for repo" do
      profile = CommunityProfile.create(repository: @repo_with_community_files)
      assert profile.issue_template
      assert_equal @repo_with_community_files, profile.issue_template.repository
    end

    test "returns org level legacy issue template" do
      org = create(:organization)
      dot_github = create(:repository, owner: org, name: ".github", from_example: :community_files_with_legacy_issue_template)
      repo = create(:repository, owner: org)

      profile = CommunityProfile.create(repository: repo)
      assert profile.issue_template
      assert_equal dot_github, profile.issue_template.repository
    end

    test "ignores legacy issue template with no content" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      refute profile.issue_template
    end
  end

  context "#pr_template" do
    test "returns pull request template for repo" do
      profile = CommunityProfile.create(repository: @repo_with_community_files)
      assert profile.pr_template
      assert_equal @repo_with_community_files, profile.pr_template.repository
    end

    test "returns org level pull request template" do
      profile = CommunityProfile.create(repository: @org_repo)
      assert profile.pr_template
      assert_equal @dot_github_repo, profile.pr_template.repository
    end

    test "ignores pull request template with no content" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      refute profile.pr_template
    end
  end

  test "#has_issue_from_non_collaborator?" do
    repo = create(:repository)
    member = create(:user)
    repo.add_member(member)
    create(:issue, repository: repo, user: member)

    profile = CommunityProfile.create(repository: repo)
    assert !profile.has_issue_from_non_collaborator?

    non_member = create(:user)
    create(:issue, repository: repo, user: non_member)
    profile.reload
    assert profile.has_issue_from_non_collaborator?
  end

  test "#has_outside_contribution?" do
    repo = create(:repository)
    member = create(:user)
    repo.add_member(member)
    CommitContribution.create(repository: repo, user: member)
    CommitContribution.create(repository: repo, user: repo.owner)
    profile = CommunityProfile.create(repository: repo)
    assert !profile.has_outside_contribution?

    non_member = create(:user)
    CommitContribution.create(repository: repo, user: non_member)
    profile.reload
    assert profile.has_outside_contribution?
  end

  context "#enqueue_help_wanted_job" do
    test "does not enqueue > 1 job for the same repo within 10 minutes", skip_enterprise: true do
      Timecop.freeze do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        tag           = "class:community_profile_update_help_wanted_counters_job"
        queued_key    = "job.once_per_interval.queued"
        duplicate_key = "job.once_per_interval.duplicate"
        user          = create(:user)
        repo          = create(:repository)

        assert_equal 0, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        CommunityProfile.enqueue_help_wanted_job(repo)

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        CommunityProfile.enqueue_help_wanted_job(repo)

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 1, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count
      end
    end

    test "enqueues different repos within 10 minutes", skip_enterprise: true do
      Timecop.freeze do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        tag           = "class:community_profile_update_help_wanted_counters_job"
        queued_key    = "job.once_per_interval.queued"
        duplicate_key = "job.once_per_interval.duplicate"
        repo          = create(:repository)
        other_repo    = create(:repository)

        assert_equal 0, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        CommunityProfile.enqueue_help_wanted_job(repo)

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        CommunityProfile.enqueue_help_wanted_job(other_repo)

        assert_equal 2, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count
      end
    end
  end

  context "#pr_or_issue_template?" do
    test "true for user owned repo with issue or pr template" do
      profile = CommunityProfile.create(repository: @repo_with_community_files)
      assert_predicate profile, :pr_or_issue_template?
    end

    test "true for org owned repo with org level issue or pr template" do
      profile = CommunityProfile.create(repository: @org_repo)
      assert_predicate profile, :pr_or_issue_template?
    end

    test "false for user owned repo without issue or pr template" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      refute_predicate profile, :pr_or_issue_template?
    end
  end

  context "#contributing?" do
    test "true for repo with contributing" do
      profile = CommunityProfile.create(repository: @repo_with_community_files)
      assert_predicate profile, :contributing?
    end

    test "true for repo with org level contributing" do
      profile = CommunityProfile.create(repository: @org_repo)
      assert_predicate profile, :contributing?
    end

    test "false for repo without contributing file" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      refute_predicate profile, :contributing?
    end
  end

  context ".tiered_reporting_enabled?" do
    test "returns true when tiered reporting is enabled" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      @repo_with_empty_template.enable_tiered_reporting(actor: @org.admin)

      assert_predicate profile, :tiered_reporting_enabled?
    end

    test "returns false when tiered reporting is not enabled" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      @repo_with_empty_template.disable_tiered_reporting(actor: @org.admin)

      refute_predicate profile, :tiered_reporting_enabled?
    end
  end

  context ".sufficient_code_of_conduct?" do
    test "returns false if code of conduct file missing" do
      profile = CommunityProfile.create(repository: @repo_with_empty_template)
      refute_predicate profile, :sufficient_code_of_conduct?
    end

    test "returns false if code of conduct file empty" do
      profile = CommunityProfile.create(repository: @repo_with_blank_coc)
      refute_predicate profile, :sufficient_code_of_conduct?
    end

    test "returns false if code of conduct says 'No code of conduct'" do
      profile = CommunityProfile.create(repository: @repo_with_flippant_coc)
      refute_predicate profile, :sufficient_code_of_conduct?
    end

    test "returns true for anything else in the file body" do
      profile = CommunityProfile.create(repository: @repo_with_unconventional_coc)
      assert_predicate profile, :sufficient_code_of_conduct?
    end
  end
end

class CommunityProfileIssueTemplateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create :repository, owner: @owner, from_example: :simple

    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)
    @dot_github_repo = create(:repository, owner: @org, name: ".github", from_example: :community_files)
  end

  test "returns true for 2 issue templates, 1 with contents" do
    issue_templates_commit = @repo.commits.create({ message: "Add filled template", committer: @owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/filled.md", <<~MARKDOWN
      ---
      name: Filled template
      about: It's got contents
      ---
      Look, contents
      MARKDOWN

      files.add ".github/ISSUE_TEMPLATE/empty.md", <<~MARKDOWN
      ---
      name: Empty template
      about: No contents =[
      ---
      MARKDOWN
    end

    @repo.refs["refs/heads/master"].update(issue_templates_commit, @owner)

    profile = CommunityProfile.create(repository: @repo)

    assert profile.issue_template?
  end

  test "returns false for 1 issue template with no contents" do
    issue_templates_commit = @repo.commits.create({ message: "Add filled template", committer: @owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/empty.md", <<~MARKDOWN
      ---
      name: Empty template
      about: No contents =[
      ---
      MARKDOWN
    end

    @repo.refs["refs/heads/master"].update(issue_templates_commit, @owner)

    profile = CommunityProfile.create(repository: @repo)

    refute profile.issue_template?
  end

  test "returns false for 0 issue templates" do
    profile = CommunityProfile.create(repository: @repo)

    refute profile.issue_template?
  end

  test "returns true for repo with org level issue templates" do
    profile = CommunityProfile.create(repository: @org_repo)
    assert profile.issue_template?
  end
end
