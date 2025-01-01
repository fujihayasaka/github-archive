# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySecurityCenterConfigTest < GitHub::IntegrationTestCase
  fixtures do
    @business = create(:business)
    @org = create(:organization, business: @business)
    @org_repo = create(:private_repository, owner: @org)
    @org_config = RepositorySecurityCenterConfig.create!({
      repository_id: @org_repo.id,
      owner_id: @org_repo.owner_id,
      business_id: @business.id,
      owner_type: "ORGANIZATION",
    })

    @user = create(:user)
    @user_repo = create(:private_repository, owner: @user)
    @user_config = RepositorySecurityCenterConfig.create!({
      repository_id: @user_repo.id,
      owner_id: @user_repo.owner_id,
      business_id: @business.id,
      owner_type: "USER",
    })
  end

  context "associations" do
    test "belongs to a repository" do
      assc_config = @org_repo.repository_security_center_config
      assert_equal @org_config.id, assc_config.id
    end

    test "many configs belong to an organization" do
      assc_configs = @org.repository_security_center_configs
      assert_equal 1, assc_configs.size
      assc_config = assc_configs.first
      assert_equal @org_config.id, assc_config.id
    end

    test "many configs belong to a user" do
      assc_configs = @user.repository_security_center_configs
      assert_equal 1, assc_configs.size
      assc_config = assc_configs.first
      assert_equal @user_config.id, assc_config.id
    end
  end

  context "scope: with_owners_under_business" do
    test "includes records for org-owned repositories" do
      cfgs = RepositorySecurityCenterConfig.with_owners_under_business(@business, [@org])

      assert_equal 1, cfgs.size
      assert_equal T.must(cfgs.first).id, @org_config.id
    end

    test "includes records for user-owned repositories" do
      cfgs = RepositorySecurityCenterConfig.with_owners_under_business(@business, [@org], include_emus: true)

      assert_equal 2, cfgs.size
      assert_same_elements [@org_config.id, @user_config.id], cfgs.map(&:id)
    end

    test "does not show any user owned results if include_emus is false" do
      rando = create(:user)
      user_repo = create(:private_repository, owner: rando)
      user_config = RepositorySecurityCenterConfig.create!({
        repository_id: user_repo.id,
        owner_id: user_repo.owner_id,
        business_id: @business.id,
        owner_type: "USER",
      })

      # By passing @org, we are kinda "faking" CAP filtering taking place, even
      # though we have not explicitly added the user to the org with the right roles
      cfgs = RepositorySecurityCenterConfig.with_owners_under_business(@business, [@org], include_emus: false)

      assert_equal 1, cfgs.size
      assert_same_elements [@org_config.id], cfgs.map(&:id)
    end
  end
end
