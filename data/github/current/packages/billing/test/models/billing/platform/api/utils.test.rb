# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::UtilsTest < GitHub::TestCase
  include Billing::Platform::Api::Utils

  class TestSubject
    include Billing::Platform::Api::Utils
  end

  setup do
    @owner = create :user
    @business_org_admin = create :user
    @billing_manager = create :user

    @business = create :business, owners: [@owner]
    @business.billing.add_manager(@billing_manager, actor: @business.owners.first)
    @business_org = create :enterprise_linked_organization, admins: [@business_org_admin], business: @business
    @repo = create(:repository, owner: @business_org, private: true)
    @business.reload

    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)
    @org.billing.add_manager(@billing_manager, actor: @owner)
    @org_repo = create(:repository, owner: @org, private: true)
  end

  context "#targets_owned_by_user?" do
    context "as a business owner" do
      test "authorized for enterprise/customer" do
        assert TestSubject.new.targets_owned_by_user?(target_type: CUSTOMER_TARGET, target_ids: [@business.customer.id], current_user: @owner, this_entity: @business)
      end

      test "authorized for organization" do
        assert TestSubject.new.targets_owned_by_user?(target_type: ORGANIZATION_TARGET, target_ids: [@business_org.id], current_user: @owner, this_entity: @business)
      end

      test "authorized for cost center" do
        assert TestSubject.new.targets_owned_by_user?(target_type: COSTCENTER_TARGET, target_ids: ["uuid"], current_user: @owner, this_entity: @business)
      end

      test "authorized for repository for owned org" do
        @business_org.add_admin(@owner)
        assert TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@repo.id], current_user: @owner, this_entity: @business)
      end

      test "not authorized for repository outside of ownership " do
        @business_org.remove_member!(@owner)
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@repo.id], current_user: @owner, this_entity: @business)
      end

      test "not authorized for repository owned outside of business" do
        repo = create(:repository, owner: @owner)
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [repo.id], current_user: @owner, this_entity: @business)
      end
    end

    context "as a billing manager" do
      test "authorized for enterprise/customer" do
        assert TestSubject.new.targets_owned_by_user?(target_type: CUSTOMER_TARGET, target_ids: [@business.customer.id], current_user: @billing_manager, this_entity: @business)
      end

      test "authorized for organization" do
        assert TestSubject.new.targets_owned_by_user?(target_type: ORGANIZATION_TARGET, target_ids: [@business_org.id], current_user: @billing_manager, this_entity: @business)

      end

      test "authorized for cost center" do
        assert TestSubject.new.targets_owned_by_user?(target_type: COSTCENTER_TARGET, target_ids: ["uuid"], current_user: @billing_manager, this_entity: @business)
      end

      test "authorized for repository for owned org" do
        @business_org.add_admin(@billing_manager)
        assert TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@repo.id], current_user: @billing_manager, this_entity: @business)
      end

      test "not authorized for repository outside of ownership " do
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@repo.id], current_user: @billing_manager, this_entity: @business)
      end

      test "not authorized for repository owned outside of business" do
        repo = create(:repository, owner: @billing_manager)
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [repo.id], current_user: @billing_manager, this_entity: @business)
      end

      test "authorized for repository for organization billing manager" do
        assert TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@org_repo.id], current_user: @billing_manager, this_entity: @org)
      end
    end

    context "as a org admin" do
      test "not authorized for enterprise/customer" do
        refute TestSubject.new.targets_owned_by_user?(target_type: CUSTOMER_TARGET, target_ids: [@business.customer.id], current_user: @business_org_admin, this_entity: @business)
      end

      test "not authorized for organization" do
        refute TestSubject.new.targets_owned_by_user?(target_type: ORGANIZATION_TARGET, target_ids: [@business_org.id], current_user: @business_org_admin, this_entity: @business)
      end

      test "authorized for cost center" do
        assert TestSubject.new.targets_owned_by_user?(target_type: COSTCENTER_TARGET, target_ids: ["uuid"], current_user: @business_org_admin, this_entity: @business)
      end

      test "authorized for repository within owned org" do
        assert TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@repo.id], current_user: @business_org_admin, this_entity: @business)
      end

      test "not authorized for repository from unowned org within business" do
        other_org = create :enterprise_linked_organization, admins: [@owner], business: @business
        repo = create(:repository, owner: other_org)
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [repo.id], current_user: @business_org_admin, this_entity: @business)
      end

      test "not authorized for repository owned outside of business" do
        repo = create(:repository, owner: @billing_manager)
        refute TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [repo.id], current_user: @business_org_admin, this_entity: @business)
      end
    end

    context "as an org admin of an org" do
      test "authorized for customer for organization owner" do
        assert TestSubject.new.targets_owned_by_user?(target_type: CUSTOMER_TARGET, target_ids: [@org.customer.id], current_user: @owner, this_entity: @org)
      end

      test "authorized for repository for organization owner" do
        assert TestSubject.new.targets_owned_by_user?(target_type: REPOSITORY_TARGET, target_ids: [@org_repo.id], current_user: @owner, this_entity: @org)
      end
    end

    context "should_filter_usage_for_business?" do
      test "returns false for non business entity" do
        org = create :organization, admins: [@owner]

        refute TestSubject.new.should_filter_usage_for_business?(org, @owner)
      end

      test "returns false for business owner" do
        refute TestSubject.new.should_filter_usage_for_business?(@business, @owner)
      end

      test "returns false for business manager" do
        refute TestSubject.new.should_filter_usage_for_business?(@business, @billing_manager)
      end

      test "returns true for non-owner, non-business-manager for business" do
        assert TestSubject.new.should_filter_usage_for_business?(@business, @business_org_admin)
      end
    end
  end
end
