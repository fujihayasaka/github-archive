# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class BusinessUserAccountUpdateAttributesTest < GitHub::TestCase
    fixtures do
      @org = create :organization
      @org2 = create :organization
      @private_repo_user = create :user
      @private_repo = create(:private_repository, :minimal, owner: @org)
      @private_repo_org2 = create(:private_repository, :minimal, owner: @org2)

      @public_repo_user = create :user
      @public_repo = create(:public_repository, :minimal, owner: @org)

      @member = create :user

      @business = create :business, organizations: [@org, @org2]

      @emu_business = create(:business, :enterprise_managed)
      @emu_owner = @emu_business.owners.first
      @emu_org = create(:organization, business: @emu_business, admin: @emu_owner)
      @emu = create :emu, business: @emu_business
    end

    setup do
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        @private_repo.add_member(@private_repo_user)
        @public_repo.add_member(@public_repo_user)
        @org.add_member @member
        @emu_org.add_member(@emu)
      end
      @member_bua = @business.business_user_account_for(@member)
    end

    def update_user_account_attributes(business: @business, user_account_ids: nil)
      attributes = BusinessUserAccount::UpdateAttributes.new(business: business, user_account_ids: user_account_ids)
      attributes.save!
      @member_bua.reload
    end

    context "user_account_ids" do
      test "only updates accounts with id included" do
        update_user_account_attributes user_account_ids: []
        assert_same_elements [], @member_bua.business_roles
        update_user_account_attributes user_account_ids: [@member_bua.id]
        assert_same_elements [:member], @member_bua.business_roles
      end
    end

    context "roles" do
      test "saves member role to user" do
        # Roles are empty for new users
        assert_same_elements [], @member_bua.business_roles

        update_user_account_attributes
        assert_same_elements [:member], @member_bua.business_roles
      end

      test "saves outside collaborator role to user" do
        private_repo_user_bua = @business.business_user_account_for(@private_repo_user)
        private_repo_user_bua.update(business_roles_bitfield: nil)
        public_repo_user_bua = @business.business_user_account_for(@public_repo_user)
        public_repo_user_bua.update(business_roles_bitfield: nil)

        assert_same_elements [], private_repo_user_bua.business_roles
        assert_same_elements [], public_repo_user_bua.business_roles

        update_user_account_attributes

        assert_same_elements [:outside_collaborator], private_repo_user_bua.reload.business_roles
        assert_same_elements [:outside_collaborator], public_repo_user_bua.reload.business_roles
      end

      test "saves unaffiliated role to user" do
        emu = create :emu
        update_user_account_attributes(business: emu.enterprise_managed_business)
        emu_bua = emu.enterprise_managed_business.business_user_account_for(emu)
        assert_equal 0, emu_bua.business_roles_bitfield
        assert_same_elements [:unaffiliated], emu_bua.business_roles
        assert emu_bua.has_business_role?(:unaffiliated)
      end

      test "saves server member role to user" do
        business_installation = create(:enterprise_installation, owner: @business)

        create :enterprise_installation_user_account, \
          enterprise_installation: business_installation,
          site_admin: false,
          business_user_account: create(:business_user_account, business: @business)

        create :enterprise_installation_user_account, \
          enterprise_installation: business_installation,
          site_admin: true,
          business_user_account: @member_bua

        update_user_account_attributes
        bua = BusinessUserAccount.last
        assert_same_elements [:server_member], bua.business_roles
        assert_same_elements [:member, :server_admin], @member_bua.business_roles
      end

      test "sets guest collaborator role when otherwise unaffiliated" do
        emu = create :emu
        guest_collaborator_unaffiliated = create :emu, :guest_collaborator, business: emu.enterprise_managed_business, login: "guest-collaborator"
        update_user_account_attributes(business: emu.enterprise_managed_business)
        emu_bua = emu.enterprise_managed_business.business_user_account_for(guest_collaborator_unaffiliated)
        assert_same_elements [:guest_collaborator], emu_bua.business_roles
        assert emu_bua.has_business_role?(:guest_collaborator)
      end

      test "sets multiple roles for users with multiple roles" do
        @private_repo_org2.add_member(@member)
        update_user_account_attributes

        assert_same_elements [:member, :outside_collaborator], @member_bua.business_roles
      end

      test "removes roles from users with existing role assignments when keeping unaffiliated accounts" do
        GitHub.flipper[:unaffiliated_user_accounts].enable
        update_user_account_attributes
        assert_same_elements [:member], @member_bua.business_roles

        @org.remove_member_without_callbacks_and_notifications(@member)

        update_user_account_attributes
        assert_same_elements [:unaffiliated], @member_bua.business_roles
      end

      test "removes user accounts for users becoming unaffiliated when removing unaffiliated accounts" do
        @business.stubs(:supports_unaffiliated_user_accounts?).returns(false)
        GitHub.flipper[:remove_unaffiliated_users_from_business].enable

        update_user_account_attributes
        assert_same_elements [:member], @member_bua.business_roles

        @org.remove_member_without_callbacks_and_notifications(@member)

        BusinessUserAccount::UpdateAttributes.new(business: @business).save!
        assert_nil @business.business_user_account_for(@member)
      end

      test "does not remove user accounts for users becoming unaffiliated when ff is off" do
        @business.stubs(:supports_unaffiliated_user_accounts?).returns(false)
        GitHub.flipper[:remove_unaffiliated_users_from_business].disable

        update_user_account_attributes
        assert_same_elements [:member], @member_bua.business_roles

        @org.remove_member_without_callbacks_and_notifications(@member)

        BusinessUserAccount::UpdateAttributes.new(business: @business).save!
        refute_nil @business.business_user_account_for(@member)
      end

      test "upgrades roles and removes old role if needed" do
        update_user_account_attributes
        private_repo_user_bua = @business.business_user_account_for(@private_repo_user)

        # Verify role is set correctly
        assert_same_elements [:outside_collaborator], private_repo_user_bua.business_roles

        # Upgrade outside collaborator to org admin
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @org.add_admin(@private_repo_user)
        end

        # This user is an org admin. Since this user now has org membership, they are no longer an outside collaborator
        update_user_account_attributes
        private_repo_user_bua.reload
        assert_same_elements [:member], private_repo_user_bua.business_roles
      end

      test "upgrades roles and keeps old role if needed" do
        update_user_account_attributes
        private_repo_user_bua = @business.business_user_account_for(@private_repo_user)

        # Verify role is set correctly
        assert_same_elements [:outside_collaborator], private_repo_user_bua.business_roles

        # Upgrade outside collaborator to owner
        @business.add_owner(@private_repo_user, actor: @business.admins.first)

        # This user is a business owner. Because they don't have org membership, they are still an outside collaborator
        # in their org.
        update_user_account_attributes
        private_repo_user_bua.reload
        assert_same_elements [:owner, :outside_collaborator], private_repo_user_bua.business_roles
      end

      test "stores emu admin roles to emu first admin" do
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        emu_owner_bua = @emu_business.business_user_account_for(@emu_owner)

        assert emu_owner_bua.business_roles.include?(:emu_admin)
      end

      test "sets suspended and removes all other roles" do
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        emu_bua = @emu_business.business_user_account_for(@emu)
        assert emu_bua.business_roles.include?(:member)

        @emu.external_identities.first.disable
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        assert_equal [:suspended], emu_bua.reload.business_roles
      end

      test "removes suspended role when account is no longer suspended" do
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        emu_bua = @emu_business.business_user_account_for(@emu)

        @emu.external_identities.first.disable
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        assert_equal [:suspended], emu_bua.reload.business_roles

        @emu.external_identities.first.enable
        attributes = BusinessUserAccount::UpdateAttributes.new(business: @emu_business.reload)
        attributes.save!
        assert_equal [:member], emu_bua.reload.business_roles
      end
    end

    context "batching" do
      test "updates_exceed_batch_size? is true if role updates is more than batch size" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        attributes = BusinessUserAccount::UpdateAttributes.new(business: @business)

        BusinessUserAccount::UpdateAttributes.stub_const(:MAX_ROLE_UPDATES, 1) do
          assert attributes.updates_exceed_batch_size?
        end
      end

      test "updates_exceed_batch_size? is false if role updates is less than batch size" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        attributes = BusinessUserAccount::UpdateAttributes.new(business: @business)

        refute attributes.updates_exceed_batch_size?
      end

      test "will read a subset of accounts if exceeding read batch size" do
        # Create clean slate for this test, since we don't know how many users are in all tests
        update_user_account_attributes

        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        # Only one account was updated when the read batch size was set to 1
        assert_difference("BusinessUserAccount.where(business_id: @business.id).with_business_role(:member).count", 1) do
          BusinessUserAccount::UpdateAttributes.stub_const(:MAX_ROLE_UPDATES, 1) do
            update_user_account_attributes
          end
        end
      end

      test "will read all accounts if batch size is not exceeded" do
        # Create clean slate for this test, since we don't know how many users are in all tests
        update_user_account_attributes

        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        # All accounts were updated when batch size not set
        assert_difference("BusinessUserAccount.where(business_id: @business.id).with_business_role(:member).count", 4) do
          update_user_account_attributes
        end
      end

      test "saves multiple accounts at a time" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        # Create clean slate for this test, since we don't know how many users are in all tests
        update_user_account_attributes

        # Create some role altering events
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        attributes = BusinessUserAccount::UpdateAttributes.new(business: @business)

        clusters_write_count = {
          ApplicationRecord::Collab => 2, # 1 for roles + 1 for licenses
        }

        assert_query_count_against_primary(clusters_and_counts: clusters_write_count) do
          attributes.save!
        end
      end

      test "saves accounts in batches if exceeding batch size" do
        @business.customer.update!(metered_plan: true, billed_via_billing_platform: true)
        Billing::Platform::Api::Client.any_instance.stubs(:get_customer).with(
          equals({ customer_id: @business.customer.id })
        ).returns({ "customer": { "customerId": @business.customer.id.to_s } })
        # Create clean slate for this test, since we don't know how many users are in all tests
        update_user_account_attributes

        # Create some role altering events
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          4.times do
            @org.add_member(create :user)
          end
        end

        attributes = BusinessUserAccount::UpdateAttributes.new(business: @business)

        clusters_write_count = {
          ApplicationRecord::Collab => 8, # 4 users * (1 role + 1 license)
        }

        assert_query_count_against_primary(clusters_and_counts: clusters_write_count) do
          BusinessUserAccount::UpdateAttributes.stub_const(:SQL_BATCH_SIZE, 1) do
            attributes.save!
          end
        end
      end
    end
  end
end
