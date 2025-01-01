# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalIdentityGroupMembershipTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @business = create :business, :enterprise_managed
    @provider = create :business_saml_provider, business: @business

    @organization_admin = create :emu, business: @business
    @org = create :organization, business: @business, admin: @organization_admin

    @external_group = create :external_group, business: @business
    @external_group_team = create :team, organization: @org
    ExternalGroupTeam.create(external_group: @external_group, team: @external_group_team)

    @user = create :emu, business: @business
    @user2 = create :emu, business: @business

    @external_user_identity = @user.external_identities.first
    @external_user_identity2 = @user2.external_identities.first

    @team = create(:team, organization: @org)
  end

  context "validations" do
    test "create a external identity group membership succeeds" do
      ExternalGroupTeam.create(external_group: @external_group, team: @team)
      external_identity_group_membership \
       = ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_user_identity)

      refute_nil external_identity_group_membership
      assert_equal @external_group.id, external_identity_group_membership.external_group_id
      assert_equal @external_user_identity.id, external_identity_group_membership.external_identity_id
    end

    test "external group required" do
      external_identity_group_membership = ExternalIdentityGroupMembership.create(external_identity: @external_user_identity)
      refute_predicate external_identity_group_membership, :valid?
      assert_includes external_identity_group_membership.errors[:external_group], "can't be blank"
    end

    test "external identity required" do
      external_identity_group_membership = ExternalIdentityGroupMembership.create(external_group: @external_group)
      refute_predicate external_identity_group_membership, :valid?
      assert_includes external_identity_group_membership.errors[:external_identity], "can't be blank"
    end
  end

  context "group scim data" do
    test "valid group scim data" do
      ExternalGroupTeam.create(external_group: @external_group, team: @team)
      ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_user_identity)
      ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @external_user_identity2)

      assert_includes @external_group.scim_group_data.fetch_all("members"), { "name" => "members", "value" => @external_user_identity.guid, "metadata" => {} }
      assert_includes @external_group.scim_group_data.fetch_all("members"), { "name" => "members", "value" => @external_user_identity2.guid, "metadata" => {} }
    end
  end
end
