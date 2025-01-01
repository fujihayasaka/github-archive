# typed: true
# frozen_string_literal: true

require "test_helper"

class RepairIssuesIndexTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @github_org = create(:organization, login: "github")
  end

  setup do
    @index = Elastomer::Indexes::Issues.new
    @index_name = @index.name
    @cluster_name = ::Elastomer.router.cluster_for_index(@index_name)
    @repair_job = RepairIssuesIndexJob.new(@index_name, { cluster: @cluster_name })
    @repair_job.reset!
  end

  context "db lookup" do
    context "issues" do
      test "ignores issues in inactive repositories" do
        repo = create(:repository, organization: @github_org)
        issue1 = create(:issue, repository: repo)

        inactive_repo = create(:repository, organization: @github_org, active: false)
        issue2 = create(:issue, repository: inactive_repo)

        models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

        assert_equal [issue1.id], models
      end

      test "ignores issues in repositories with issues disabled" do
        repo = create(:repository, organization: @github_org)
        issue1 = create(:issue, repository: repo)

        repo_without_issues = create(:repository, organization: @github_org, has_issues: false)
        issue2 = create(:issue, repository: repo_without_issues)

        models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

        assert_equal [issue1.id], models
      end

      test "ignores issues in spammy repositories", skip_enterprise: true do # Spam check is not available in GHE
        repo = create(:repository, organization: @github_org)
        issue1 = create(:issue, repository: repo)

        spammy_owner = create(:user, spammy: true)
        spammy_repo = create(:repository, organization: @github_org, owner: spammy_owner)
        issue2 = create(:issue, repository: spammy_repo)

        models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

        assert_equal [issue1.id], models
      end

      test "ignores issues in repositories owned by trade restricted users" do
        repo = create(:repository, organization: @github_org)
        issue1 = create(:issue, repository: repo)

        owner = create(:user)
        restricted_repo = create(:private_repository, organization: @github_org, owner: owner)
        issue2 = create(:issue, repository: restricted_repo)
        owner.trade_controls_restriction.full!

        models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

        assert_equal [issue1.id], models
      end

      test "ignores issues in disabled repositories" do
        repo = create(:repository, organization: @github_org)
        issue1 = create(:issue, repository: repo)

        staff_user = create(:user, :staff)
        disabled_repo = create(:repository, organization: @github_org)
        issue2 = create(:issue, repository: disabled_repo)
        disabled_repo.access.disable("size", staff_user)

        models = @repair_job.reconcilers.flat_map { |r| r.lookup_from_db.keys }

        assert_equal [issue1.id], models
      end
    end
  end
end
