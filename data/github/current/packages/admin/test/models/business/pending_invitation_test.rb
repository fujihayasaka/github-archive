# typed: true
# frozen_string_literal: true

require "test_helper"

class PendingInvitationTest < GitHub::TestCase
  fixtures do
    @rando = create :user
    @org_admin = create :user
    @bus_owner = create :user

    @org = create :organization, admins: [@org_admin]
    @scim_org = create :organization, admins: [@org_admin]
    @business = create :business, owners: [@bus_owner], organizations: [@scim_org, @org]
    create :business_saml_provider, :scim_provisioning_enabled, business: @business

    # SAML user
    @saml_user = create(:user, email: "saml-user@example.com")
    create(:external_identity,
      provider: @business.saml_provider,
      user: @saml_user,
      saml_user_data: Platform::Provisioning::SamlUserData.new([
        { "name" => "NameID", "value" => "saml-user" },
        { "name" => "emails", "value" => "saml-nameid-emails@github.com" },
      ]))

    # SCIM user provisioned with an existing user account - manual invitation
    @scim_linked_user = create(:user, email: "scim-username@example.com")
    create(:external_identity,
      provider: @business.saml_provider,
      user: @scim_linked_user,
      scim_user_data: Platform::Provisioning::ScimUserData.new([
        { "name" => "externalId", "value" => "scim-username" },
        { "name" => "userName", "value" => "scim-username@github.com" },
      ]))

    # SCIM provisioned user with no existing user account - automatic invitation
    @scim_unlinked_user_email = "scim-unlinked-user@example.com"
    scim_unlinked_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
    scim_unlinked_user_data.append "userName", @scim_unlinked_user_email
    Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(
      organization_id: @scim_org.id,
      user_data: scim_unlinked_user_data,
      inviter_id: @org_admin,
      mapper: Platform::Provisioning::ScimMapper)
  end

  context "#scim_provisioned?" do
    test "false for random user invite" do
      @scim_org.invite @rando, inviter: @org_admin
      invitation = @business.filtered_pending_invitations(query: @rando.login).first
      refute invitation.scim_provisioned?
    end

    test "false for email invite" do
      @scim_org.invite(email: "rando@example.com", inviter: @org_admin)
      invitation = @business.filtered_pending_invitations(query: "rando@example.com").first
      refute invitation.scim_provisioned?
    end

    test "false for SAML user invitation" do
      @scim_org.invite @saml_user, inviter: @org_admin
      invitation = @business.filtered_pending_invitations(query: @saml_user.login).first
      refute invitation.scim_provisioned?
    end

    test "true for SCIM invites provisioned by SCIM sync" do
      invitation = @business.filtered_pending_invitations(query: @scim_unlinked_user_email).first
      assert invitation.scim_provisioned?
    end

    test "false for SCIM user with manual org invitation" do
      @org.invite @scim_linked_user, inviter: @org_admin
      invitation = @business.filtered_pending_invitations(query: @scim_linked_user.login).first
      refute invitation.scim_provisioned?
    end

    test "false for SCIM provisioned user invited by email address" do
      @org.invite(email: @scim_unlinked_user_email, inviter: @org_admin)
      invitation = @business.filtered_pending_invitations(organizations: [@org.login]).first
      refute invitation.scim_provisioned?
    end

    test "false for SCIM user invited to business without SCIM provider" do
      nonscim_org = create :organization, admins: [@org_admin]
      nonscim_business = create :business, owners: [@bus_owner], organizations: [nonscim_org]

      nonscim_org.invite @scim_linked_user, inviter: @org_admin

      nonscim_invite = nonscim_business.filtered_pending_invitations(query: @scim_linked_user.login).first
      refute nonscim_invite.scim_provisioned?
    end
  end
end unless GitHub.bypass_org_invites_enabled?
