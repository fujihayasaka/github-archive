# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOrganizationMembersTest < GitHub::TestCase
  fixtures do
    @business = create(:business)

    @organization1_admin = create(:user)
    @organization2_admin = create(:user)
    @organization1_member_reader = create(:user)
    @both_organizations_member = create(:user)
    @no_organizations_member = create(:user)
    @organization1_outside_collaborator = create(:user)

    @organization1 = create(:organization, business: @business, admins: [@organization1_admin])
    @organization2 = create(:organization, business: @business, admins: [@organization2_admin])

    @organization1.add_member(@organization1_member_reader, action: :read)
    @organization1.add_member(@both_organizations_member, action: :read)
    @organization2.add_member(@both_organizations_member, action: :read)

    @organization1_private_repository = create(:private_repository, :minimal, owner: @organization1)
    @organization1_private_repository.add_member(@organization1_outside_collaborator)
  end

  context "#organization_members" do
    test "returns unique users who are members of any of the enterprise account's organizations" do
      assert_same_elements(
        [@organization1_admin, @organization2_admin, @organization1_member_reader, @both_organizations_member],
        @business.organization_members
      )
    end

    test "can be limited to a subset of organizations' members" do
      assert_same_elements(
        [@organization1_admin, @organization1_member_reader, @both_organizations_member],
        @business.organization_members(org_ids: [@organization1.id])
      )
    end

    test "can be limited to a subset of actions" do
      assert_same_elements(
        [@organization1_admin, @organization2_admin],
        @business.organization_members(action: :admin)
      )
    end

    test "can be limited to a subset of members (AKA actors)" do
      assert_same_elements(
        [@organization1_admin, @both_organizations_member],
        @business.organization_members(actor_ids: [@organization1_admin.id, @both_organizations_member.id, @no_organizations_member.id])
      )
    end

    test "returns an empty relation when there are no organizations" do
      @organization1.destroy
      @organization2.destroy

      assert_empty @business.organization_members
    end
  end

  context "#organization_member_ids" do
    test "returns unique users who are members of any of the enterprise account's organizations" do
      assert_same_elements(
        [@organization1_admin.id, @organization2_admin.id, @organization1_member_reader.id, @both_organizations_member.id],
        @business.organization_member_ids
      )
    end

    test "can be limited to a subset of organizations' members" do
      assert_same_elements(
        [@organization1_admin.id, @organization1_member_reader.id, @both_organizations_member.id],
        @business.organization_member_ids(org_ids: [@organization1.id])
      )
    end

    test "can be limited to a subset of actions" do
      assert_same_elements(
        [@organization1_admin.id, @organization2_admin.id],
        @business.organization_member_ids(action: :admin)
      )
    end

    test "can be limited to a subset of members (AKA actors)" do
      assert_same_elements(
        [@organization1_admin.id, @both_organizations_member.id],
        @business.organization_member_ids(actor_ids: [@organization1_admin.id, @both_organizations_member.id, @no_organizations_member.id])
      )
    end

    test "returns an empty array when there are no organizations" do
      @organization1.destroy
      @organization2.destroy

      assert_empty @business.organization_member_ids
    end
  end
end
