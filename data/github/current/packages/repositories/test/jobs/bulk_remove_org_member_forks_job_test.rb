# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkRemoveOrgMemberForksJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization, name: "org1")
    @org.allow_private_repository_forking(actor: @org.admin)
    @org.add_member(@user)
    @owner = @org.admin

    @biz_admin = create(:user)
    @business_1 = create(:business, owners: [@biz_admin])
    @biz_org_1, @biz_org_2 = create(:organization), create(:organization)

    @business_1.add_organization(@biz_org_1)
    @biz_org_1.allow_private_repository_forking(actor: @biz_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @biz_org_2.allow_private_repository_forking(actor: @biz_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @private_repo = create(:private_repository, :minimal, owner: @org)
    @private_repo2 = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
    @repo = create :private_repository, owner: @org
  end

  test "#perform should not remove fork if user does not exist" do
    assert_no_difference("Repository.count") do
      BulkRemoveOrgMemberForksJob.perform_now(organization_ids: [@org.id], user_id: "not_a_user")
    end
  end

  test "#perform should not remove fork if organization_ids is empty" do
    assert_no_difference("Repository.count") do
      BulkRemoveOrgMemberForksJob.perform_now(organization_ids: [], user_id: @user.id)
    end
  end

  test "#perform should remove multiple repository forks from multiple orgs" do
    removed_user = create(:user)
    @org.add_member(removed_user)
    org2 = create(:organization, name: "org2")
    org2.add_member(removed_user)
    org2.allow_private_repository_forking(actor: org2.admin)

    org1_repo_1 = create :private_repository, owner: @org, name: "123"
    org1_repo_2 = create :private_repository, owner: @org, name: "456"
    org2_repo_1 = create :private_repository, owner: org2, name: "789"

    removed_user_fork_1, reason = org1_repo_1.fork(forker: removed_user)
    assert removed_user_fork_1, "Fork should have succeeded but failed with reason '#{reason}'"
    removed_user_fork_2, reason = org1_repo_2.fork(forker: removed_user)
    assert removed_user_fork_1, "Fork should have succeeded but failed with reason '#{reason}'"
    removed_user_fork_3, reason = org2_repo_1.fork(forker: removed_user)
    assert removed_user_fork_1, "Fork should have succeeded but failed with reason '#{reason}'"

    unrelated_user_fork = @private_repo.fork(forker: (create :user))

    @org.remove_member_without_callbacks_and_notifications(removed_user)
    org2.remove_member_without_callbacks_and_notifications(removed_user)

    assert_difference("Repository.active.count", -3) do
      BulkRemoveOrgMemberForksJob.perform_now(user_id: removed_user.id, organization_ids: [@org.id, org2.id])
    end
  end

  test "#perform should remove multiple repository forks from multiple business", skip_enterprise: true do
    business_2 = create(:business, owners: [@biz_admin])
    business_2.add_organization(@biz_org_2)

    removed_user = create(:user)
    @biz_org_1.add_member(removed_user)
    @biz_org_2.add_member(removed_user)
    org1_repo_1 = create(:private_repository, owner: @biz_org_1)
    org2_repo_1 = create(:private_repository, owner: @biz_org_2)

    user_fork_1, reason = org1_repo_1.fork(forker: removed_user)
    assert user_fork_1, "Fork should have succeeded but failed with reason '#{reason}'"
    user_fork_2, reason = org2_repo_1.fork(forker: removed_user)
    assert user_fork_2, "Fork should have succeeded but failed with reason '#{reason}'"

    other_user_fork = @private_repo.fork(forker: (create :user))

    @biz_org_1.remove_member_without_callbacks_and_notifications(removed_user)
    @biz_org_2.remove_member_without_callbacks_and_notifications(removed_user)

    ::RemoveBizUserForksJob.expects(:perform_later)
      .once
      .with(biz_id: @business_1.id, belonging_to_user_id: removed_user.id)

    ::RemoveBizUserForksJob.expects(:perform_later)
      .once
      .with(biz_id: business_2.id, belonging_to_user_id: removed_user.id)

    assert_difference("Repository.active.count", -2) do
      BulkRemoveOrgMemberForksJob.perform_now(user_id: removed_user.id, organization_ids: [@biz_org_1.id, @biz_org_2.id])
    end
  end

  test "#perform should run RemoveBizUserForksJob only once when 2 organizations from the same business are passed" do
    @business_1.add_organization(@biz_org_2)
    removed_user = create(:user)
    @biz_org_1.add_member(removed_user)
    @biz_org_2.add_member(removed_user)
    org1_repo_1 = create(:private_repository, owner: @biz_org_1)
    org2_repo_1 = create(:private_repository, owner: @biz_org_2)

    user_fork_1, reason = org1_repo_1.fork(forker: removed_user)
    assert user_fork_1, "Fork should have succeeded but failed with reason '#{reason}'"
    user_fork_2, reason = org2_repo_1.fork(forker: removed_user)
    assert user_fork_2, "Fork should have succeeded but failed with reason '#{reason}'"

    other_user_fork = @private_repo.fork(forker: (create :user))

    @biz_org_1.remove_member_without_callbacks_and_notifications(removed_user)
    @biz_org_2.remove_member_without_callbacks_and_notifications(removed_user)

    ::RemoveBizUserForksJob.expects(:perform_later)
      .once
      .with(biz_id: @business_1.id, belonging_to_user_id: removed_user.id)

    assert_difference("Repository.active.count", -2) do
      BulkRemoveOrgMemberForksJob.perform_now(user_id: removed_user.id, organization_ids: [@biz_org_1.id, @biz_org_2.id])
    end
  end
end
