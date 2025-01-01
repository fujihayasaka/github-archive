# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseContributionTest < GitHub::TestCase
  include GitHubConnectHelper

  fixtures do
    @user = create(:user)
    @another_user = create(:user)
    @yet_another_user = create(:user)
    @org = create(:organization, admin: @user)
    @installation = create :enterprise_installation
    @another_installation = create :enterprise_installation
    create(:dotcom_user, user_id: @user.id)
  end

  setup do
    EnterpriseContribution.destroy_all
    EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.today, 1)
    GitHub.enable_dotcom_contributions(@user)
    DotcomConnection.new.authentication_token = "qwerty"
  end

  context "#insert_or_update_contribution" do
    test "creates contribution for date" do
      assert_equal 1, @user.enterprise_contributions.for_date(Date.today).first.count
    end

    test "updates contribution for date" do
      EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.today, 10)
      assert_equal 10, @user.enterprise_contributions.for_date(Date.today).first.count
    end

    test "deletes contribution if count is 0" do
      EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.today, 0)
      assert_equal 0, @user.enterprise_contributions.for_date(Date.today).count
    end
  end

  context "clear_installation_contributions!" do
    test "deletes all enterprise contributions for an enterprise installation" do
      EnterpriseContribution.insert_or_update_contribution(@another_user, @installation, Date.today, 2)

      assert_equal 2, @installation.enterprise_contributions.count

      EnterpriseContribution.clear_installation_contributions!(@installation.id)
      assert_equal 0, @installation.enterprise_contributions.count
    end

    test "clears contribution graph cache for all users that had contributions (and only those)" do
      EnterpriseContribution.insert_or_update_contribution(@another_user, @installation, Date.today, 2)
      EnterpriseContribution.insert_or_update_contribution(@yet_another_user, @another_installation, Date.today, 2)

      Contribution.expects(:clear_caches_for_user).with(@user, context: "clear_enterprise_installation_contributions").once
      Contribution.expects(:clear_caches_for_user).with(@another_user, context: "clear_enterprise_installation_contributions").once
      Contribution.expects(:clear_caches_for_user).with(@yet_another_user, context: "clear_enterprise_installation_contributions").never

      EnterpriseContribution.clear_installation_contributions!(@installation.id)
    end

    test "deletes enterprise contributions even after their installation is gone" do
      EnterpriseContribution.insert_or_update_contribution(@another_user, @installation, Date.today, 2)
      installation_id = @installation.id
      @installation.destroy!

      assert_equal 2, @installation.enterprise_contributions.count

      EnterpriseContribution.clear_installation_contributions!(installation_id)
      assert_equal 0, @installation.enterprise_contributions.count
    end

    test "runs deletion job for installation enterprise contributions" do
      assert_enqueued_with(job: GitHubConnectDestroyInstallationContributionsJob, args: [@installation.id]) do
        EnterpriseContribution.clear_installation_contributions(@installation)
      end
    end
  end

  context "clear_user_contributions!" do
    test "deletes user contributions for a particular enterprise installation" do
      EnterpriseContribution.insert_or_update_contribution(@user, @another_installation, Date.today, 2)

      assert_equal 2, @user.enterprise_contributions.count

      EnterpriseContribution.clear_user_contributions!(@user, @installation.id)
      assert_equal 1, @user.enterprise_contributions.count
    end

    test "clears contribution graph cache for the user" do
      EnterpriseContribution.insert_or_update_contribution(@user, @another_installation, Date.today, 2)

      Contribution.expects(:clear_caches_for_user).with(@user, context: "clear_enterprise_user_contributions")

      EnterpriseContribution.clear_user_contributions!(@user, @installation.id)
    end

    test "deletes user contributions even after their installation is gone" do
      EnterpriseContribution.insert_or_update_contribution(@user, @another_installation, Date.today, 2)
      installation_id = @installation.id
      @installation.destroy!

      assert_equal 2, @user.enterprise_contributions.count

      EnterpriseContribution.clear_user_contributions!(@user, installation_id)
      assert_equal 1, @user.enterprise_contributions.count
    end

    test "runs deletion job for user enterprise contributions" do
      assert_enqueued_with(job: GitHubConnectDestroyUserContributionsJob, args: [@user, @installation.id]) do
        EnterpriseContribution.clear_user_contributions(@user, @installation)
      end
    end
  end

  test "#push_user_contributions_history counts user contributions and posts them (via #post_contribution_data)" do
    if GitHub.enterprise?
      GitHub::Connect.expects(:post_contribution_data).with(&contributions(@user, count: 1))
      EnterpriseContribution.push_user_contributions_history(@user)
    end
  end

  test "#push_new_contributions runs job to push new contributions" do
    if GitHub.enterprise?
      assert_enqueued_with(job: GitHubConnectPushNewContributionsJob, args: nil) do
        EnterpriseContribution.push_new_contributions
      end
    end
  end
end
