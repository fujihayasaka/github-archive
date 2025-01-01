# typed: false
# frozen_string_literal: true

require "test_helper"

module ExternalGroupSharedTests
  extend ActiveSupport::Concern
  include Api::Serializer::ScimDependency
  include GitHub::LoggerHelper
  include ExternalGroupHelpers
  include AuditLog::IntegrationTestHelpers

  def url(value)
    value
  end

  included do
    context "validations" do
      test "create a external group succeeds" do
        external_group_id = SecureRandom.uuid
        external_group = ExternalGroup.create(
            provider: @provider,
            external_id: external_group_id,
            display_name: @display_name
        )
        refute_nil external_group
        assert_equal @provider.id, external_group.provider_id
        assert_equal external_group_id, external_group.external_id
        assert_equal @display_name, external_group.display_name
      end

      test "identity provider required" do
        external_group = ExternalGroup.create(external_id: @external_id, display_name: @display_name)
        refute_predicate external_group, :valid?
      end

      test "external id required" do
        external_group = ExternalGroup.create(provider: @provider, display_name: @display_name)
        refute_predicate external_group, :valid?
      end

      test "display name required" do
        external_group = ExternalGroup.create(provider: @provider, external_id: @external_id)
        refute_predicate external_group, :valid?
      end

      test "long display_name returns an error message" do
        external_group = build :external_group, provider: @provider, display_name: "a" * 500, external_id: @external_group_id
        refute_predicate external_group, :valid?
        assert_equal "Display name (SCIM: displayName) is too long (maximum is 128 characters).",
          external_group.errors.full_messages.first
        assert_equal [:too_long], external_group.errors.details[:display_name].pluck(:error)
      end

      test "long external_id returns an error message" do
        external_group = build :external_group, provider: @provider, external_id: "a" * 500, display_name: @display_name
        refute_predicate external_group, :valid?
        assert_equal "External id (SCIM: externalId) is too long (maximum is 128 characters).",
          external_group.errors.full_messages.first
        assert_equal [:too_long], external_group.errors.details[:external_id].pluck(:error)
      end

      test "4-byte characters in display_name raises ActiveRecord::RecordInvalid" do
        external_group = build :external_group, provider: @provider, display_name: "🍣", external_id: @external_group_id
        refute_predicate external_group, :valid?
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Display name contains invalid 4-byte characters") do
          external_group.save!
        end
      end
    end

    context "guid" do
      test "sets a guid for an external group" do
        external_group = create(:external_group)
        assert_predicate external_group, :guid?
        refute_nil external_group.guid
      end
    end

    context "delete" do
      test "successfully delete the external group" do
        external_group1 = create(:external_group)
        external_group2 = create(:external_group)
        assert_nil(external_group1.deleted_at, "deleted_at should be nil for newly created external group")
        external_group1.mark_group_deleted
        refute_nil(external_group1.deleted_at, "deleted_at should not be nil for deleted external group")
        assert_same_elements [@external_group, external_group2], ExternalGroup.not_deleted
        @external_group.mark_group_deleted
        external_group2.mark_group_deleted
        assert_empty ExternalGroup.not_deleted
      end

      test "successfully restore the external group" do
        external_group = create(:external_group)
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        external_group.mark_group_deleted
        refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
        assert_equal [@external_group], ExternalGroup.not_deleted
        external_group.restore_group
        assert_nil(external_group.deleted_at, "deleted_at should be nil for restored external group")
        assert_same_elements [@external_group, external_group], ExternalGroup.not_deleted
      end

      test "marking group as deleted removes group memberships" do
        external_group = create :external_group, :with_members, number_of_members: 2, business: @business
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_equal 2, external_group.external_identity_group_memberships.count
        perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
          external_group.mark_group_deleted
          external_group.save
          refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
        end
        assert_equal 0, external_group.reload.external_identity_group_memberships.count
      end

      test "marking group as deleted removes group and team memberships" do
        external_group = create :external_group, :with_team, :with_members, number_of_members: 2, business: @business
        team = external_group.external_group_teams.first.team
        assert_equal 2, team.member_ids.count
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_equal 2, external_group.external_identity_group_memberships.count
        perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
          external_group.mark_group_deleted
          external_group.save
          refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
        end

        assert_equal 2, team.reload.member_ids.count
        perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]

        assert_equal 0, external_group.reload.external_identity_group_memberships.count
        assert_equal 0, team.reload.member_ids.count
      end

      test "marking group as deleted removes group but not enterprise team group mapping if enterprise teams is disabled" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
        external_group = create :external_group, :with_members, number_of_members: 2, business: @business
        enterprise_team = create(:enterprise_team, business: @business)
        enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should be nil for newly created enterprise team group mapping")
        assert_equal 2, external_group.external_identity_group_memberships.count
        perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob, ClearEnterpriseTeamGroupMappingsJob]) do
          external_group.mark_group_deleted
          external_group.save
          enterprise_team_group_mapping.reload
          refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
          assert_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should not be nil for deleted enterprise team group mapping")
        end
        assert_equal 0, external_group.reload.external_identity_group_memberships.count
      end

      test "marking group as deleted removes group and enterprise team group mapping if enterprise on basic plan" do
        @business.update(seats_plan_type: :basic)
        external_group = create :external_group, :with_members, number_of_members: 2, business: @business
        enterprise_team = create(:enterprise_team, business: @business)
        enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should be nil for newly created enterprise team group mapping")
        assert_equal 2, external_group.external_identity_group_memberships.count
        perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob, ClearEnterpriseTeamGroupMappingsJob]) do
          external_group.mark_group_deleted
          external_group.save
          enterprise_team_group_mapping.reload
          refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
          refute_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should not be nil for deleted enterprise team group mapping")
        end
        assert_equal 0, external_group.reload.external_identity_group_memberships.count
      end unless GitHub.single_business_environment?

      test "marking group as deleted removes group and enterprise team group mapping if enterprise on full plan with org sync support" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
        external_group = create :external_group, :with_members, number_of_members: 2, business: @business
        enterprise_team = create(:enterprise_team, business: @business)
        enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should be nil for newly created enterprise team group mapping")
        assert_equal 2, external_group.external_identity_group_memberships.count
        perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob, ClearEnterpriseTeamGroupMappingsJob]) do
          external_group.mark_group_deleted
          external_group.save
          enterprise_team_group_mapping.reload
          refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
          refute_nil(enterprise_team_group_mapping.deleted_at, "deleted_at should not be nil for deleted enterprise team group mapping")
        end
        assert_equal 0, external_group.reload.external_identity_group_memberships.count
      end unless GitHub.single_business_environment?

      test "passes and logs caller param on ExternalGroupMemberReconcileJob when marking group as deleted" do
        external_group = create :external_group, :with_team, :with_members, number_of_members: 2, business: @business
        team = external_group.external_group_teams.first.team
        assert_equal 2, team.member_ids.count
        assert_nil(external_group.deleted_at, "deleted_at should be nil for newly created external group")
        assert_equal 2, external_group.external_identity_group_memberships.count

        base_log = {
          "gh.caller" => "ExternalGroup"
        }
        log_1 = base_log.merge({ "info.message" => "Starting external_group_member_reconcile_job" })
        log_2 = base_log.merge({ "info.message" => "Finished external_group_member_reconcile_job" })

        assert_logged(**log_1) do
          assert_logged(**log_2) do
            perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
              external_group.mark_group_deleted
              external_group.save
              refute_nil(external_group.deleted_at, "deleted_at should not be nil for deleted external group")
            end
          end
        end
      end
    end

    context "by provider" do
      test "find external group by provider" do
        assert_equal ExternalGroup.by_provider(@provider).first, @external_group
      end

      test "find external group by business provider" do
        assert_equal ExternalGroup.by_provider(@provider), [@external_group]

        external_group = ExternalGroup.create(provider: @provider, external_id: "4c31ae34-d538-4921-992c-d79651226a20", display_name: "SAML group")

        assert_same_elements ExternalGroup.by_provider(external_group.provider), [@external_group, external_group]
        assert_same_elements @business.external_provider.external_groups.not_deleted, [@external_group, external_group]
      end
    end

    context "by external_id" do
      test "find external group by external_id" do
        external_group = create(:external_group)
        assert_nil ExternalGroup.find_by_external_id(SecureRandom.uuid), external_group
        assert_equal ExternalGroup.find_by_external_id(external_group.external_id), external_group
      end
    end

    context "by guid" do
      test "find external group by guid" do
        external_group = create(:external_group)
        assert_nil ExternalGroup.find_by_guid("invalid guid")
        assert_equal ExternalGroup.find_by_guid(external_group.guid), external_group
      end
    end

    context "order_by_display_name_desc" do
      test "orders external groups by display name descending" do
        external_group_2 = create(:external_group, display_name: "Zoo")
        assert_equal ExternalGroup.order_by_display_name_desc, [external_group_2, @external_group]
      end
    end

    context "test factories" do
      test "ten members created after external_group is created with test factories" do
        external_group = create :external_group, :with_members, number_of_members: 10
        assert_equal 10, external_group.external_identity_group_memberships.count
      end

      test "destroy external_identity_memberships when external_group destroyed" do
        external_group = create :external_group, :with_members, number_of_members: 10
        assert_difference "ExternalIdentityGroupMembership.count", -10 do
          external_group.destroy
        end
      end
    end

    context ".scim_filter" do
      test 'supports `id eq "<id>"` filters' do
        results = ExternalGroup.scim_filter(%Q{id eq "#{ @external_group.guid }"})
        assert_same_elements [@external_group], results
      end

      test 'supports `displayName eq "<displayName>"` filters' do
        results = ExternalGroup.scim_filter(%Q{displayName eq "#{ @external_group.display_name }"})
        assert_same_elements [@external_group], results
      end

      test 'supports `externalId eq "<externalId>"` filters' do
        results = ExternalGroup.scim_filter(%Q{externalId eq "#{ @external_group.external_id }"})
        assert_same_elements [@external_group], results
      end

      test "is case insensitive" do
        results = ExternalGroup.scim_filter(%Q{externalid EQ "#{ @external_group.external_id }"})
        assert_same_elements [@external_group], results
      end

      test "does not support 'and' filters" do
        assert_raises SCIM::Filter::InvalidFilterError do
          ExternalGroup.scim_filter(%Q{id eq "#{ @external_group.guid }" and externalId eq "#{ @external_group.external_id }"})
        end
      end

      test "does not support other filters than EQ" do
        assert_raises SCIM::Filter::InvalidFilterError do
          ExternalGroup.scim_filter(%Q{id co "#{ @external_group.guid }"})
        end
      end
    end

    context ".with_scim_preloads" do
      test "runs 4 queries and preloads target in enterprise" do
        groups = assert_query_count(4, ignore_feature_flags: true) do
          ExternalGroup.with_scim_preloads.to_a
        end

        assert_predicate groups.first.association(:provider), :loaded?
        assert_predicate groups.first.provider.association(:target), :loaded?
      end if GitHub.enterprise?

      test "runs 4 queries and preloads target" do
        groups = assert_query_count(4, ignore_feature_flags: true) do
          ExternalGroup.with_scim_preloads_emu.to_a
        end

        assert_predicate groups.first.association(:provider), :loaded?
        assert_predicate groups.first.provider.association(:target), :loaded?
      end unless GitHub.enterprise?

      test "runs 6 queries and preloads all associations" do
        external_group = create :external_group, :with_members, business: @business, number_of_members: 10

        groups = assert_query_count(6, ignore_feature_flags: true) do
          ExternalGroup.where(guid: external_group.guid).with_scim_preloads.to_a
        end

        assert_predicate groups.first.association(:provider), :loaded?
        assert_predicate groups.first.provider.association(:target), :loaded?
        assert_predicate groups.first.association(:external_identity_group_memberships), :loaded?
        assert_predicate groups.first.external_identity_group_memberships.first.association(:external_identity), :loaded?
        assert_predicate groups.first.external_identity_group_memberships.first.external_identity.association(:display_name_records), :loaded?

        assert_query_count(0, ignore_feature_flags: true) do
          enterprise_scim_group_hash(groups.first)
        end
      end if GitHub.enterprise?

      test "runs 7 queries and preloads all associations" do
        external_group = create :external_group, :with_members, business: @business, number_of_members: 10

        groups = assert_query_count(7, ignore_feature_flags: true) do
          ExternalGroup.where(guid: external_group.guid).with_scim_preloads_emu.to_a
        end

        assert_predicate groups.first.association(:provider), :loaded?
        assert_predicate groups.first.provider.association(:target), :loaded?
        assert_predicate groups.first.association(:external_identity_group_memberships), :loaded?
        assert_predicate groups.first.external_identity_group_memberships.first.association(:external_identity), :loaded?
        assert_predicate groups.first.external_identity_group_memberships.first.external_identity.association(:user), :loaded?
        assert_predicate groups.first.external_identity_group_memberships.first.external_identity.user.association(:profile), :loaded?

        assert_query_count(0, ignore_feature_flags: true) do
          enterprise_scim_group_hash(groups.first)
        end
      end unless GitHub.enterprise?
    end

    context "instruments tests" do
      test "update_display_name" do
        events = subscribe "external_group.update_display_name"
        group = create :external_group, :with_team

        group.instrument_event(:update_display_name)

        expected_payload = {
          operation: :update_display_name,
          external_group_id: group.id,
          external_group: group.display_name,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "update" do
        events = subscribe "external_group.update"
        group = create :external_group, :with_team

        group.instrument_event(:update)

        expected_payload = {
          operation: :update,
          external_group_id: group.id,
          external_group: group.display_name,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "provision" do
        events = subscribe "external_group.provision"
        group = create :external_group, :with_team

        group.instrument_event(:provision)

        expected_payload = {
          operation: :provision,
          external_group_id: group.id,
          external_group: group.display_name,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "deprovision" do
        events = subscribe "external_group.delete"
        group = create :external_group, :with_team

        group.instrument_event(:delete)

        expected_payload = {
          operation: :delete,
          external_group_id: group.id,
          external_group: group.display_name,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "link" do
        # This method call results in a call to instrument update within the model.
        group = nil
        events = assert_performed_audit_entries(count: 1, only: "external_group.link") do
          perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
            group = create :external_group, :with_team
          end
        end
        external_group_team = group.external_group_teams.first
        team = external_group_team.team

        expected_payload = {
          operation: :link,
          external_group: group.display_name,
          external_group_id: group.id,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          team: team.name,
          team_id: team.id,
          scim_group_id: group.guid,
          org: team.organization.login,
          org_id: team.organization.id
        }

        assert event = events.pop, "an event was expected"
        assert_subset_hash expected_payload, event
      end

      test "unlink" do
        group = create :external_group, :with_team
        external_group_team = group.external_group_teams.first
        team = external_group_team.team

        # This method call results in a call to instrument update within the model.
        events = assert_performed_audit_entries(count: 1, only: "external_group.unlink") do
          perform_enqueued_jobs(only: [ExternalGroupTeamUnlinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
            external_group_team.destroy
          end
        end

        expected_payload = {
          operation: :unlink,
          external_group: group.display_name,
          external_group_id: group.id,
          team: team.name,
          team_id: team.id,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          scim_group_id: group.guid,
          org: team.organization.login,
          org_id: team.organization.id,
        }

        assert event = events.pop, "an event was expected"
        assert_subset_hash expected_payload, event
      end

      test "add_member" do
        events = subscribe "external_group.add_member"
        group = create :external_group, :with_members, number_of_members: 2, business: @business

        user = create @user_factory, business: @business
        ExternalIdentityGroupMembership.create(external_group: group, external_identity: user.external_identities.first)
        group.instrument_event(:add_member, nil, user: user)

        expected_payload = {
          operation: :add_member,
          external_group: group.display_name,
          external_group_id: group.id,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          user: user.display_login,
          user_id: user.id,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "remove_member" do
        events = subscribe "external_group.remove_member"
        group = create :external_group, :with_members, number_of_members: 2, business: @business
        user = create @user_factory, business: @business

        group.instrument_event(:remove_member, nil, user: user)

        expected_payload = {
          operation: :remove_member,
          external_group: group.display_name,
          external_group_id: group.id,
          external_group_external_id: group.external_id,
          provider_type: group.provider_type,
          user: user.display_login,
          user_id: user.id,
          scim_group_id: group.guid,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "#member_user_ids" do
      test "returns the user ids of the members of the external group with members" do
        external_group = create(:external_group, :with_members, business: @business).reload
        assert_equal 5, external_group.member_user_ids.size
      end

      test "returns no user ids of the members of the external group without members" do
        external_group = create(:external_group, business: @business).reload
        assert_equal 0, external_group.member_user_ids.size
      end
    end

    context "#active_user_ids" do
      test "returns the user ids of the members of the external group with members" do
        external_group = create(:external_group, :with_members, business: @business).reload
        assert_equal 5, external_group.active_user_ids.size
      end

      test "returns no user ids of the members of the external group without members" do
        external_group = create(:external_group, business: @business).reload
        assert_equal 0, external_group.active_user_ids.size
      end

      test "returns user ids of the members of the external group without disabled members" do
        external_group = create(:external_group, :with_members, business: @business).reload
        external_identity = external_group.members.first.external_identity
        external_identity.disable

        assert_equal 4, external_group.active_user_ids.size

        external_identity.enable
        assert_equal 5, external_group.active_user_ids.size
      end
    end

    context "#active_user?" do
      test "returns true if user is member of the external group " do
        external_group = create(:external_group, :with_members, business: @business).reload

        assert external_group.active_user?(external_group.active_user_ids.first)
      end

      test "returns false if member of the external group is deprovisioned" do
        external_group = create(:external_group, :with_members, business: @business).reload
        user = external_group.members.first
        external_identity = user.external_identity
        external_identity.disable

        refute external_group.active_user?(user.id)
      end

      test "returns false if user is not a member of the external group" do
        external_group = create(:external_group, :with_members, business: @business).reload
        user = create :user
        create :external_identity, provider: @provider, user: user

        refute external_group.active_user?(user.id)
      end
    end

    context "#has_guest_collaborators?" do
      test "returns false when not an EMU group" do
        refute_predicate @external_group, :has_guest_collaborators?
      end
    end if GitHub.single_business_environment?

    context "#group_and_team_memberships_match?" do
      test "true when there are no mismatches" do
        assert_predicate @external_group, :group_and_team_memberships_match?
      end

      test "false when the sync status is not synced" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_with_members = create(:external_group, :with_members, business: @business, number_of_members: 2)
          org = create(:organization, seats: 10, business: @business)
          team = create(:team, organization: org)

          external_group_team = ExternalGroupTeam.create(external_group: external_group_with_members, team: team)

          # symbolically out of sync
          external_group_team.update(sync_status: ExternalGroupTeam.sync_statuses["out_of_sync_generic"])
          # actually out of sync
          former_team_member = team.members.first
          team.remove_member(former_team_member, force: true)

          assert external_group_with_members.member? former_team_member.external_identities.first.id
          refute team.member? former_team_member
          assert_equal external_group_team.team.id, team.id
          assert_equal external_group_team.external_group.id, external_group_with_members.id

          refute_predicate external_group_with_members, :group_and_team_memberships_match?
        end
      end
    end
  end
end

class EMUExternalGroupTest < GitHub::TestCase
  include ExternalGroupSharedTests

  fixtures do
    @user_factory = :emu
    @business_admin = create :user
    @not_emu_business = create(:business, :default_managed, owners: [@business_admin])
    @not_emu_provider = create(:business_saml_provider, business: @not_emu_business)

    @business = create(:business, :enterprise_managed)
    @provider = create(:business_saml_provider, business: @business)

    @external_group_id = "4c31ae02-d538-4921-992c-d79651226a99"
    @display_name = "Existing Group"
    @external_group = ExternalGroup.create(provider: @provider, external_id: @external_group_id, display_name: @display_name)
  end

  setup do
    disable_feature_flag(:disable_external_group_member_reconcile_job)
    disable_feature_flag(:disable_external_group_team_reconcile_job)
  end

  context "validations" do
    test "can be created with Business::OIDCProvider" do
      oidc_business = create(:business, :enterprise_managed)
      oidc_provider = create(:business_oidc_provider, business: oidc_business)

      external_group_id = "4c31ae34-d538-4921-992c-d79651226a29"
      display_name = "OIDC Group"
      oidc_external_group = ExternalGroup.create(provider: oidc_provider, external_id: external_group_id, display_name: display_name)

      assert_predicate oidc_external_group, :valid?
      refute_nil oidc_external_group
      assert_equal oidc_provider.id, oidc_external_group.provider_id
      assert_equal external_group_id, oidc_external_group.external_id
      assert_equal display_name, oidc_external_group.display_name
    end

    test "can be only created with business saml provider for now" do
      org = create(:business_plus_organization)
      provider = create :organization_saml_provider, organization: org
      external_group = ExternalGroup.create(
        provider: provider,
        external_id:  SecureRandom.uuid,
        display_name: @display_name
      )
      refute_predicate external_group, :valid?
    end

    test "can be only created with emu enabled business" do
      external_group = ExternalGroup.create(
        provider: @not_emu_provider,
        external_id:  SecureRandom.uuid,
        display_name: @display_name
      )
      refute_predicate external_group, :valid?
    end
  end

  context "by provider" do
    test "find external group by Business::OIDCProvider" do
      oidc_business = create(:business, :enterprise_managed)
      oidc_provider = create(:business_oidc_provider, business: oidc_business)
      assert_empty ExternalGroup.by_provider(oidc_provider)

      oidc_external_group = ExternalGroup.create(provider: oidc_provider, external_id: "4c31ae34-d538-4921-992c-d79651226a29", display_name: "OIDC Group")

      assert_equal ExternalGroup.by_provider(oidc_external_group.provider).first, oidc_external_group
      assert_equal oidc_business.external_provider.external_groups.not_deleted, [oidc_external_group]
    end
  end

  context "#has_guest_collaborators?" do
    test "returns false when group has no guest collaborators" do
      refute_predicate @external_group, :has_guest_collaborators?
    end

    test "returns true when group has guest collaborators" do
      guest_collaborator = create :emu, :guest_collaborator, business: @business
      external_group_with_guest_collaborators = create :external_group, :with_members, users: [guest_collaborator], business: @business

      assert_predicate external_group_with_guest_collaborators, :has_guest_collaborators?
    end
  end

  context "#external_group_ids_with_guest_collaborator" do
    test "returns empty set when group has no guest collaborators" do
      assert_empty ExternalGroup.external_group_ids_with_guest_collaborator([@external_group.id])
    end

    test "returns expected result when group has guest collaborators" do
      guest_collaborator = create :emu, :guest_collaborator, business: @business
      external_group_with_guest_collaborators = create :external_group, :with_members, users: [guest_collaborator], business: @business

      ids = [external_group_with_guest_collaborators.id, @external_group.id]
      assert_same_elements [external_group_with_guest_collaborators.id], ExternalGroup.external_group_ids_with_guest_collaborator(ids)
    end

    test "does not include disabled guest collaborators" do
      guest_collaborator = create :emu, :guest_collaborator, business: @business
      guest_collaborator.external_identities.first.disable
      external_group_with_guest_collaborators = create :external_group, :with_members, users: [guest_collaborator], business: @business

      ids = [external_group_with_guest_collaborators.id, @external_group.id]
      assert_empty ExternalGroup.external_group_ids_with_guest_collaborator(ids)
    end

    test "does not include deleted guest collaborators" do
      guest_collaborator = create :emu, :guest_collaborator, business: @business
      guest_collaborator.external_identities.first.mark_deleted
      external_group_with_guest_collaborators = create :external_group, :with_members, users: [guest_collaborator], business: @business

      ids = [external_group_with_guest_collaborators.id, @external_group.id]
      assert_empty ExternalGroup.external_group_ids_with_guest_collaborator(ids)
    end
  end

  context "#enterprise_team_group_mappings" do
    test "returns empty array when no enterprise_team_group_mappings exist" do
      external_group = create(:external_group, :with_members, business: @business)
      assert_empty(external_group.enterprise_team_group_mappings)
    end

    test "returns enterprise_team_group_mappings in array when enterprise_team_group_mappings exist" do
      external_group = create(:external_group, :with_members, business: @business)
      enterprise_team = create :enterprise_team, business: @business
      enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(
          enterprise_team: enterprise_team,
          external_group: external_group
        )
      assert_equal([enterprise_team_group_mapping], external_group.enterprise_team_group_mappings)
    end
  end

  context "#enterprise_teams" do
    test "returns empty array when no enterprise_team_group_mappings exist" do
      external_group = create(:external_group, :with_members, business: @business)
      assert_empty(external_group.enterprise_team_group_mappings)
    end

    test "returns enterprise_team_group_mappings in array when enterprise_team_group_mappings exist" do
      external_group = create(:external_group, :with_members, business: @business)
      enterprise_team = create :enterprise_team, business: @business
      enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(
          enterprise_team: enterprise_team,
          external_group: external_group
        )
      assert_equal([enterprise_team], external_group.enterprise_teams)
    end
  end
end unless GitHub.single_business_environment?

class GHESWithSCIMExternalGroupTest < GitHub::TestCase
  include ExternalGroupSharedTests
  include AuthenticationHelpers::SAML

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @user_factory = :ghes_scim_user
    @business = create(:global_business)
    @provider = @business.external_provider

    @external_group_id = "4c31ae02-d538-4921-992c-d79651226a99"
    @display_name = "Existing Group"

    @external_group = ExternalGroup.create(provider: @provider, external_id: @external_group_id, display_name: @display_name)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
