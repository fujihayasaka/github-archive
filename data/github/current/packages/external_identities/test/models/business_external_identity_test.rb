# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalIdentitysInABusinessTest < GitHub::TestCase
  fixtures do
    @saml_user1 = create :user, login: "saml-user-1"
    @saml_user2 = create :user, login: "saml-user-2"
    @scim_user1 = create :user, login: "scim-user-1"
    @org1 = create :organization
    @org1.add_member(@saml_user1)
    @org2 = create :organization
    @collaborator = create(:user, login: "collaborator")
    @repo1 = create :repository, owner: @org1
    RepositoryInvitation.invite_to_repo_without_confirmation(
      @collaborator, @org1.admins.first, @repo1
    )
    @saml_business = create(:business, organizations: [@org1, @org2])
    GitHub.flipper[:enterprise_idp_provisioning].enable(@saml_business)
    @provider = create(:business_saml_provider, :full_user_provisioning, business: @saml_business)
    @member1_identity = create :external_identity, provider: @provider, user: @saml_user1
    scim_user_data = Platform::Provisioning::ScimUserData.new
    scim_user_data.append "userName", @scim_user1.email
    scim_user_data.append "groups", @org1.login
    @scim_identity = create(:external_identity, :scim, user: @scim_user1,
                            provider: @provider, scim_user_data: scim_user_data)
    @org1.add_member(@scim_user1)

    @org_provider = create(:organization_saml_provider)
    @saml_org = @org_provider.organization
    scim_user_data = Platform::Provisioning::ScimUserData.new
    scim_user_data.append "userName", @scim_user1.email
    @scim_org_identity = create(:external_identity, :scim, user: @scim_user1,
                                provider: @org_provider, scim_user_data: scim_user_data)
    @saml_org.add_member(@scim_user1)
  end

  def business_owner(business: @saml_business)
    @first_owner ||= business.owners.first
  end

  unless GitHub.enterprise?
    context "Business#remove_member" do
      test "preserves SCIM-provisioned business external identity" do
        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, BusinessMembershipCleanupJob]) do
            @saml_business.remove_member(@scim_user1, actor: business_owner)
          end
        end

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
      end

      test "deletes SAML-provisioned business external identity" do
        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
          perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, BusinessMembershipCleanupJob]) do
            @saml_business.remove_member(@saml_user1, actor: business_owner)
          end
        end

        refute ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "preserves external identities which have both SAML and SCIM attributes" do
        scim_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
        scim_user_data.append "userName", @member1_identity.saml_user_data.name_id
        scim_user_data.append "emails", @saml_user1.email
        scim_user_data.append "groups", @org1.login

        Platform::Provisioning::IdentityProvisioner.provision_and_invite(target: @saml_business,
          inviter_id: business_owner.id, user_data: scim_user_data,
          mapper: Platform::Provisioning::ScimMapper, identity: @member1_identity)

        assert @member1_identity.reload.identity_attribute_records.attributes_by_scheme[:scim].any?
        assert @member1_identity.identity_attribute_records.attributes_by_scheme[:saml].any?
        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, BusinessMembershipCleanupJob]) do
            @saml_business.remove_member(@saml_user1, actor: business_owner)
          end
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "preserves SCIM-provisioned identities for member org, if it also has SAML configured" do
        @saml_business.add_organization @saml_org

        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, BusinessMembershipCleanupJob]) do
          assert_no_difference("@saml_org.saml_provider.external_identities.count") do
            @saml_business.remove_member(@scim_user1, actor: business_owner)
          end
        end

        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1
      end

      test "deletes SAML-provisioned identities for member org, if it also has SAML configured" do
        create(:external_identity, user: @saml_user1, provider: @org_provider)
        @saml_org.add_member(@saml_user1)
        @saml_business.add_organization @saml_org

        assert ExternalIdentity.linked? provider: @org_provider, user: @saml_user1

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, BusinessMembershipCleanupJob, OrganizationBulkRemoveMembersCleanupJob]) do
          assert_difference("@saml_org.saml_provider.external_identities.count", -1) do
            @saml_business.remove_member(@saml_user1, actor: business_owner)
          end
        end

        refute ExternalIdentity.linked? provider: @org_provider, user: @saml_user1
      end
    end

    context "Business#remove_owner" do
      test "deletes SAML-provisioned business external identity" do
        create :external_identity, provider: @provider, user: @saml_user2
        @saml_business.add_owner(@saml_user2, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
          @saml_business.remove_owner(@saml_user2, actor: business_owner)
        end

        refute ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end

      test "keeps SCIM-provisioned business external identity" do
        @saml_business.add_owner(@scim_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.remove_owner(@scim_user1, actor: business_owner)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
      end
    end

    context "Business#add_owner" do
      test "adds owner when external identity exists for user" do
        # @saml_user1 is already provisioned with an external identity
        @saml_business.add_owner(@saml_user1, actor: business_owner)
        assert @saml_business.owner?(@saml_user1)
      end

      test "raises UserHasNoExternalIdentityError when external identity does not exist for user" do
        # @saml_user2 does not have an external identity
        assert_raises Business::UserHasNoExternalIdentityError do
          @saml_business.add_owner(@saml_user2, actor: business_owner)
        end
      end

      test "doesn't raise UserHasNoExternalIdentityError when external identity exists for oidc user" do
        emu_owner = create :emu, :owner, provider_type: :oidc
        business = emu_owner.enterprise_managed_business
        user = create :emu, business: emu_owner.enterprise_managed_business

        business.add_owner(user, actor: emu_owner)

        assert business.owner?(user)
      end
    end

    context "Business.billing#add_manager" do
      test "adds billing manager when external identity exists for user" do
        # @saml_user1 is already provisioned with an external identity
        @saml_business.billing.add_manager(@saml_user1, actor: business_owner)
        assert @saml_business.billing_manager?(@saml_user1)
      end

      test "raises UserHasNoExternalIdentityError when external identity does not exist for user" do
        # @saml_user2 does not have an external identity
        assert_raises Business::UserHasNoExternalIdentityError do
          @saml_business.billing.add_manager(@saml_user2, actor: business_owner)
        end
      end
    end

    context "Business.billing#remove_manager" do
      test "preserves SCIM-provisioned business external identity" do
        @saml_business.billing.add_manager(@scim_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.billing.remove_manager(@scim_user1, actor: business_owner)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
      end

      test "deletes SAML-provisioned business external identity" do
        create :external_identity, provider: @provider, user: @saml_user2
        @saml_business.billing.add_manager(@saml_user2, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
          @saml_business.billing.remove_manager(@saml_user2, actor: business_owner)
        end

        refute ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end
    end

    context "Business#remove_organization" do
      test "keeps SCIM identities but removes SAML ones for the org being removed" do
        scim_user_data = Platform::Provisioning::ScimUserData.new
        scim_user_data.append "userName", @org1.admin.email
        scim_user_data.append "groups", @org1.login
        create(:external_identity, :scim, user: @org1.admin,
               provider: @provider, scim_user_data: scim_user_data)

        3.times do
          user = create :user
          scim_user_data = Platform::Provisioning::ScimUserData.new
          scim_user_data.append "userName", user.email
          scim_user_data.append "groups", @org1.login
          create(:external_identity, :scim, user: user,
                 provider: @provider, scim_user_data: scim_user_data)
          @org1.add_member(user)
        end

        create :external_identity, provider: @provider, user: @saml_user2
        @org1.add_member(@saml_user2)

        attributes = {
          provider_id: @provider.id,
          provider_type: @provider.class.name,
        }
        assert_equal @org1.members.count, ExternalIdentity.where(attributes).count
        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        perform_enqueued_jobs(only: [BusinessMembershipCleanupJob]) do
          assert_difference("@saml_business.saml_provider.external_identities.count", -2) do
            @saml_business.remove_organization(@org1)
          end
        end

        assert_equal @org1.reload.members.count - 2, ExternalIdentity.where(attributes).count
        refute ExternalIdentity.linked? provider: @provider, user: @saml_user1
        refute ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end

      test "doesn't deprovision external identity if they belong to another business org" do
        @org2.add_member(@saml_user1)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.remove_organization(@org1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "doesn't deprovision external identity if user is a billing manager of another org" do
        @org2.billing.add_manager(@saml_user1, actor: @org2.admins.first)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.remove_organization(@org1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "doesn't deprovision external identity if user is a business owner'" do
        @saml_business.add_owner(@saml_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.remove_organization(@org1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "doesn't deprovision external identity if user is a business billing manager" do
        @saml_business.billing.add_manager(@saml_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @saml_business.remove_organization(@org1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end
    end

    context "Organization#remove_member" do
      test "preserves SCIM external identity when user is removed" do
        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_no_difference("@saml_business.saml_provider.external_identities.count") do
            @org1.remove_member(@scim_user1)
          end
        end

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
      end

      test "deletes SAML external identity when user is removed" do
        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
            @org1.remove_member(@saml_user1)
          end
        end

        refute ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "preserves SCIM external identity for SAML-enabled org that belongs to business" do
        @saml_business.add_organization @saml_org

        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_no_difference("@saml_org.saml_provider.external_identities.count") do
            @saml_org.remove_member(@scim_user1)
          end
        end

        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1
      end

      test "deletes SAML external identity for SAML-enabled org that belongs to business" do
        create :external_identity, provider: @org_provider, user: @saml_user2
        @saml_org.add_member(@saml_user2)
        @saml_business.add_organization @saml_org

        assert ExternalIdentity.linked? provider: @org_provider, user: @saml_user2

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_difference("@saml_org.saml_provider.external_identities.count", -1) do
            @saml_org.remove_member(@saml_user2)
          end
        end

        refute ExternalIdentity.linked? provider: @org_provider, user: @saml_user2
      end

      test "deprovisions SAML external identity for an org admin" do
        org_admin = create :user
        create :external_identity, provider: @provider, user: org_admin
        @org1.add_admin(org_admin)

        assert ExternalIdentity.linked? provider: @provider, user: org_admin

        perform_enqueued_jobs(only: [RemoveOrgAdminJob, RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
            @org1.remove_member(org_admin)
          end
        end

        refute ExternalIdentity.linked? provider: @provider, user: org_admin
      end

      test "keeps SCIM external identity for an org admin" do
        org_admin = create :user
        scim_user_data = Platform::Provisioning::ScimUserData.new
        scim_user_data.append "userName", org_admin.email
        scim_user_data.append "groups", @org1.login
        @scim_org_identity = create(:external_identity, :scim, user: org_admin,
                                    provider: @provider, scim_user_data: scim_user_data)
        @org1.add_admin(org_admin)

        assert ExternalIdentity.linked? provider: @provider, user: org_admin

        perform_enqueued_jobs(only: [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]) do
          assert_no_difference("@saml_business.saml_provider.external_identities.count") do
            @org1.remove_member(org_admin)
          end
        end

        assert ExternalIdentity.linked? provider: @provider, user: org_admin
      end

      test "keeps SAML external identity for user if they belong to another org in the business" do
        @org2.add_member(@saml_user1)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.remove_member(@saml_user1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "keeps SAML external identity for user if they're a billing manager in another business org" do
        @org2.billing.add_manager(@saml_user1, actor: @org2.admins.first)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.remove_member(@saml_user1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "keeps SAML business external identity if user is a business owner" do
        @saml_business.add_owner(@saml_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.remove_member(@saml_user1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "keeps SAML business external identity if user is a business billing manager" do
        @saml_business.billing.add_manager(@saml_user1, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.remove_member(@saml_user1)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user1
      end

      test "deprovisions SAML external identity if user is only an outside collab for the business" do
        create :external_identity, provider: @provider, user: @collaborator
        @org2.add_member(@collaborator)
        assert @saml_business.outside_collaborators.include?(@collaborator)
        assert @org1.user_is_outside_collaborator?(@collaborator.id)

        assert ExternalIdentity.linked? provider: @provider, user: @collaborator

        only = [RemoveOrgMemberJob, BusinessMembershipCleanupJob, RevokeOrgMembershipAbilitiesJob]
        perform_enqueued_jobs(only: only) do
          assert_difference("@saml_business.saml_provider.external_identities.count", -1) do
            @org2.remove_member(@collaborator)
          end
        end

        assert @saml_business.outside_collaborators.include?(@collaborator)
        refute ExternalIdentity.linked? provider: @provider, user: @collaborator
      end
    end

    context "Organization.billing#remove_manager" do
      test "preserves both org and business SCIM identities for an org billing manager" do
        @saml_org.remove_member(@scim_user1)
        @saml_org.billing.add_manager(@scim_user1, actor: @saml_org.admins.first)
        @saml_business.add_organization @saml_org

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          assert_no_difference("@saml_org.saml_provider.external_identities.count") do
            @saml_org.reload.billing.remove_manager(@scim_user1, actor: @saml_org.admins.first)
          end
        end

        assert ExternalIdentity.linked? provider: @provider, user: @scim_user1
        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1
      end

      test "keeps SAML external identity if billing manager is a member of another business org" do
        create :external_identity, provider: @provider, user: @saml_user2
        @org1.billing.add_manager(@saml_user2, actor: @org1.admins.first)
        @org2.add_member(@saml_user2)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.billing.remove_manager(@saml_user2, actor: @org1.admins.first)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end

      test "keeps SAML external identity if user is a billing manager of another business org" do
        create :external_identity, provider: @provider, user: @saml_user2
        @org1.billing.add_manager(@saml_user2, actor: @org1.admins.first)
        @org2.billing.add_manager(@saml_user2, actor: @org2.admins.first)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.billing.remove_manager(@saml_user2, actor: @org1.admins.first)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end

      test "keeps SAML external identity if billing manager is an owner of the business" do
        create :external_identity, provider: @provider, user: @saml_user2
        @org1.billing.add_manager(@saml_user2, actor: @org1.admins.first)
        @saml_business.add_owner(@saml_user2, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.billing.remove_manager(@saml_user2, actor: @org1.admins.first)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end

      test "keeps external identity if billing manager is also a billing manager of the business" do
        create :external_identity, provider: @provider, user: @saml_user2
        @org1.billing.add_manager(@saml_user2, actor: @org1.admins.first)
        @saml_business.billing.add_manager(@saml_user2, actor: business_owner)

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2

        assert_no_difference("@saml_business.saml_provider.external_identities.count") do
          @org1.billing.remove_manager(@saml_user2, actor: @org1.admins.first)
        end

        assert ExternalIdentity.linked? provider: @provider, user: @saml_user2
      end
    end

    context "ExternalIdentity#destroy" do
      test "when SAML provider is destroyed, deprovisions all of its external identities" do
        identity2 = create :external_identity, provider: @provider, user: @saml_user2
        @saml_business.add_owner(@saml_user2, actor: business_owner)
        billing_manager_identity = create :external_identity, provider: @provider
        @saml_business.billing.add_manager(billing_manager_identity.user, actor: business_owner)

        assert_same_elements [@member1_identity, @scim_identity, identity2, billing_manager_identity],
                             @saml_business.saml_provider.external_identities.user_identities

        assert_no_difference("@saml_org.saml_provider.external_identities.count") do
          assert_difference("@saml_business.saml_provider.external_identities.count", -4) do
            perform_enqueued_jobs(only: [DestroyExternalProviderDependentsJob]) do
              @provider.destroy
            end
          end
        end

        assert ExternalIdentity.linked? provider: @org_provider, user: @scim_user1
      end
    end

    context "ExternalIdentity#unlink" do
      test "can instrument business.revoke_external_identity event when Business identity is revoked" do
        events = subscribe "business.revoke_external_identity"

        ExternalIdentity.unlink \
          provider: @provider,
          user: @saml_user1,
          instrumentation_payload: {
            actor: business_owner,
            user: @saml_user1,
          }

        expected_payload = {
          name: @saml_business.name,
          business: @saml_business.slug,
          business_id: @saml_business.id,
          actor: business_owner.login,
          actor_id: business_owner.id,
          user: @saml_user1.login,
          user_id: @saml_user1.id,
        }

        assert event = events.pop, "business.revoke_external_identity event was expected"
        assert events.empty?
        assert_equal expected_payload, event.payload
      end
    end
  end
end
