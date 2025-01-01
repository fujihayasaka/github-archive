# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class BusinessUserAccountSynchronizeAccountsTest < GitHub::TestCase

    fixtures do
      @org = create :organization
      @member = create :user
      @org.add_member(@member)
      @private_repo_user = create :user
      @private_repo = create(:private_repository, :minimal, owner: @org)
      @private_repo.add_member(@private_repo_user)

      @unaffiliated = create :user
      @rando = create :user

      @business = create :business, organizations: [@org]

      @enterprise_user_1 = create :emu, :owner, login: "enterprise-user-1"
      @emu_business = @enterprise_user_1.enterprise_managed_business
      @emu_owner = @emu_business.find_first_emu_owner
      @emu_org = create(:organization, business: @emu_business)

      @emu_member = create :emu, business: @emu_business
      @emu_guest_collaborator_org_member = create :emu, :guest_collaborator, business: @emu_business
      @emu_guest_collaborator_unaffiliated = create :emu, :guest_collaborator, business: @emu_business

      @emu_org.add_member(@guest_collaborator_org_member)
      @emu_org.add_member(@emu_member)
    end

    setup do
      enable_feature_flag(:bua_synchronize_removes_orphaned_accounts)
      @bua_account_sync = BusinessUserAccount::SynchronizeAccounts.new(business: @business)
      @emu_account_sync = BusinessUserAccount::SynchronizeAccounts.new(business: @emu_business)

      long_time_ago = BusinessUserAccount::SynchronizeAccounts::BUA_REMOVAL_DELAY.ago - 5.minutes
      Timecop.travel(long_time_ago) do
        @business.add_user_accounts([@unaffiliated.id], business_roles_bitfield: BusinessUserAccount::Roles::BUSINESS_ROLES[:unaffiliated])
      end
    end

    context "#add_missing_accounts" do
      test "adds user accounts missing a BUA account" do
        BusinessUserAccount.where(user_id: @member.id).delete_all
        @bua_account_sync.add_missing_accounts

        assert @business.user_accounts.pluck(:user_id).include?(@member.id)
      end

      test "creates accounts for outside collaborators" do
        BusinessUserAccount.where(user_id: @private_repo_user.id).delete_all
        @bua_account_sync.add_missing_accounts

        assert @business.user_accounts.pluck(:user_id).include?(@private_repo_user.id)
      end

      test "adds missing owner accounts" do
        owner = @business.owners.first
        BusinessUserAccount.where(user_id: owner.id).delete_all
        @bua_account_sync.add_missing_accounts

        assert @business.user_accounts.pluck(:user_id).include?(owner.id)
      end

      test "adds missing billing manager accounts" do
        billing_manager = create :user
        @business.billing.add_manager billing_manager, actor: @business.owners.first
        BusinessUserAccount.where(user_id: billing_manager.id).delete_all
        @bua_account_sync.add_missing_accounts

        assert @business.user_accounts.pluck(:user_id).include?(billing_manager.id)
      end
    end

    context "#add_missing_accounts for EMU" do
      test "adds EMU first admin" do
        BusinessUserAccount.where(user_id: @emu_owner.id).delete_all
        @emu_account_sync.add_missing_accounts

        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_owner.id)
      end

      test "adds missing guest collaborator accounts" do
        BusinessUserAccount.where(user_id: @emu_guest_collaborator_org_member.id).delete_all
        @emu_account_sync.add_missing_accounts

        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_guest_collaborator_org_member.id)
      end

      test "adds missing guest collaborator unaffiliated accounts" do
        BusinessUserAccount.where(user_id: @emu_guest_collaborator_unaffiliated.id).delete_all
        @emu_account_sync.add_missing_accounts

        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_guest_collaborator_unaffiliated.id)
      end

      test "adds missing suspended members" do
        external_identity = @emu_member.external_identities.first
        external_identity.disable
        external_identity.save
        external_identity.reload
        assert_same_elements @emu_business.reload.suspended_member_ids, [@emu_member.id]

        BusinessUserAccount.where(user_id: @emu_member.id).delete_all
        @emu_account_sync.add_missing_accounts

        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_member.id)
      end
    end

    context "#remove_orphaned_accounts" do
      test "removes BUA accounts for users without business permissions, when they were added a long time ago" do
        Business.any_instance.stubs(:supports_unaffiliated_user_accounts?).returns(false)

        assert @business.user_accounts.pluck(:user_id).include?(@unaffiliated.id)
        @bua_account_sync.remove_orphaned_accounts

        refute @business.user_accounts.pluck(:user_id).include?(@unaffiliated.id)
      end

      test "does not remove newly added BUA accounts" do
        Business.any_instance.stubs(:supports_unaffiliated_user_accounts?).returns(false)

        recent_time = BusinessUserAccount::SynchronizeAccounts::BUA_REMOVAL_DELAY.ago + 5.minutes
        Timecop.travel(recent_time) do
          @business.add_user_accounts([@rando.id], business_roles_bitfield: BusinessUserAccount::Roles::BUSINESS_ROLES[:unaffiliated])
        end

        assert @business.user_accounts.pluck(:user_id).include?(@rando.id)
        @bua_account_sync.remove_orphaned_accounts

        assert @business.user_accounts.pluck(:user_id).include?(@rando.id)
      end

      test "does not remove accounts when remove FF is disabled" do
        Business.any_instance.stubs(:supports_unaffiliated_user_accounts?).returns(false)
        disable_feature_flag(:bua_synchronize_removes_orphaned_accounts)

        @bua_account_sync.remove_orphaned_accounts

        assert @business.user_accounts.pluck(:user_id).include?(@unaffiliated.id)
      end

      test "does not remove accounts when business supports unaffiliated accounts" do
        Business.any_instance.stubs(:supports_unaffiliated_user_accounts?).returns(true)
        @bua_account_sync.remove_orphaned_accounts

        assert @business.user_accounts.pluck(:user_id).include?(@unaffiliated.id)
      end

      test "does not remove accounts for EMU businesses" do
        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_guest_collaborator_unaffiliated.id)

        long_time_ago = BusinessUserAccount::SynchronizeAccounts::BUA_REMOVAL_DELAY.ago - 5.minutes
        @emu_guest_collaborator_unaffiliated.update(created_at: long_time_ago)
        @emu_account_sync.remove_orphaned_accounts

        assert @emu_business.user_accounts.pluck(:user_id).include?(@emu_guest_collaborator_unaffiliated.id)
      end
    end
  end
end
