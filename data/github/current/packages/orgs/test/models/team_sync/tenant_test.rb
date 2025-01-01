# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamSyncTenantTest < GitHub::TestCase
  include HydroTestHelpers
  extend EncryptedColumnTestHelper

  test_encrypted_column(:team_sync_tenant, :encrypted_ssws_token)

  fixtures do
    @org = create(:business_plus_org, login: "saml-org")
    @saml_provider = create(:organization_saml_provider, organization: @org, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")

    create :team_sync_tenant, organization: @org
    assert_predicate @org, :show_team_sync_feature?
  end

  test "invalid status throws an error" do
    tenant = @org.team_sync_tenant

    assert_raises ArgumentError do
      tenant.status = "blargh"
    end
  end

  test "setting an invalid provider type throws an error" do
    tenant = @org.team_sync_tenant

    assert_raises ArgumentError do
      tenant.provider_type = "blargh"
    end
  end

  test "team sync enabled for tenant?" do
    tenant = @org.team_sync_tenant
    assert_predicate tenant, :team_sync_enabled?
  end

  test "destroy removes the tenant" do
    tenant = @org.team_sync_tenant
    assert_equal "enabled", tenant.status
    tenant.destroy
    assert_nil @org.reload.team_sync_tenant
  end

  context "instrumentation emits event to GlobalInstrumenter" do
    test "when status changes to enabled" do
      tenant = create :team_sync_tenant, status: "ready"
      GlobalInstrumenter.expects(:instrument).with(
        "team_sync_tenant.status_change",
        team_sync_tenant: tenant,
        organization: tenant.organization,
        previous_status: "ready",
        current_status: "enabled",
      )
      tenant.update(status: "enabled")
    end

    test "when status changes to disabled" do
      tenant = create :team_sync_tenant, status: "enabled"
      GlobalInstrumenter.expects(:instrument).with(
        "team_sync_tenant.status_change",
        team_sync_tenant: tenant,
        organization: tenant.organization,
        previous_status: "enabled",
        current_status: "disabled",
      )
      tenant.disable
    end

    test "when okta credentials are updated" do
      tenant = create :team_sync_tenant
      events = subscribe "team_sync_tenant.update_okta_credentials"
      expected_payload = {
        team_sync_tenant_id: tenant.id,
        org: tenant.organization.to_s,
        org_id: tenant.organization.id,
        provider_id: tenant.provider_id,
      }

      tenant.update(encrypted_ssws_token: "new token", url: "https://www.updated.com")

      assert event = events.pop, "a team_sync_tenant.update_okta_credentials event was expected"
      assert_equal "team_sync_tenant.update_okta_credentials", event.name
      assert_equal event.payload, expected_payload
    end
  end

  context "hydro events are published" do
    test "when status changes to enabled" do
      tenant = create :team_sync_tenant, status: "ready"
      tenant.update(status: "enabled")
      assert_hydro_published({
        team_sync_tenant: {
          id: tenant.id,
          global_relay_id: tenant.global_relay_id,
          provider_type: :AZUREAD,
          provider_id: tenant.provider_id,
          status: :ENABLED,
          created_at: tenant.created_at,
          updated_at: tenant.updated_at,
          organization_id: tenant.organization_id,
        },
        organization: {
          id: tenant.organization.id,
          login: tenant.organization.login.to_s,
          billing_email: tenant.organization.billing_email,
          billing_plan: tenant.organization.plan.try(:display_name),
          spammy: tenant.organization.spammy?,
          suspended: tenant.organization.suspended?,
          spamurai_classification: :SPAMURAI_CLASSIFICATION_UNKNOWN,
          global_relay_id: tenant.organization.global_relay_id,
          created_at: tenant.organization.created_at,
        },
        previous_status: :READY,
        current_status: :ENABLED,
      }, schema: "github.v1.TeamSyncTenantStatusChange")
    end

    test "when status changes to disabled" do
      tenant = create :team_sync_tenant, status: "enabled"
      tenant.disable
      assert_hydro_published({
        team_sync_tenant: {
          id: tenant.id,
          global_relay_id: tenant.global_relay_id,
          provider_type: :AZUREAD,
          provider_id: tenant.provider_id,
          status: :DISABLED,
          created_at: tenant.created_at,
          updated_at: tenant.updated_at,
          organization_id: tenant.organization_id,
        },
        organization: {
          id: tenant.organization.id,
          login: tenant.organization.login.to_s,
          billing_email: tenant.organization.billing_email,
          billing_plan: tenant.organization.plan.try(:display_name),
          spammy: tenant.organization.spammy?,
          suspended: tenant.organization.suspended?,
          spamurai_classification: :SPAMURAI_CLASSIFICATION_UNKNOWN,
          global_relay_id: tenant.organization.global_relay_id,
          created_at: tenant.organization.created_at,
        },
        previous_status: :ENABLED,
        current_status: :DISABLED,
      }, schema: "github.v1.TeamSyncTenantStatusChange")
    end

    test "supports okta tenants" do
      tenant = create :team_sync_tenant, :okta
      tenant.failed!
      assert_hydro_published({
        team_sync_tenant: {
          id: tenant.id,
          global_relay_id: tenant.global_relay_id,
          provider_type: :OKTA,
          provider_id: tenant.provider_id,
          status: :FAILED,
          created_at: tenant.created_at,
          updated_at: tenant.updated_at,
          organization_id: tenant.organization_id,
        },
        organization: {
          id: tenant.organization.id,
          login: tenant.organization.login.to_s,
          billing_email: tenant.organization.billing_email,
          billing_plan: tenant.organization.plan.try(:display_name),
          spammy: tenant.organization.spammy?,
          suspended: tenant.organization.suspended?,
          spamurai_classification: :SPAMURAI_CLASSIFICATION_UNKNOWN,
          global_relay_id: tenant.organization.global_relay_id,
          created_at: tenant.organization.created_at,
        },
        previous_status: :ENABLED,
        current_status: :FAILED,
      }, schema: "github.v1.TeamSyncTenantStatusChange")
    end
  end

  test "disable removes existing group mappings" do
    tenant = create :team_sync_tenant
    org = tenant.organization
    team = create(:team, organization: org)
    create(:team_group_mapping, team: team, tenant: tenant)

    assert_predicate tenant, :enabled?
    assert_difference "tenant.team_group_mappings.count", -1 do
      tenant.disable
    end
  end

  test "#disable does not change status if mappings destruction fails" do
    tenant = create :team_sync_tenant
    org = tenant.organization
    team = create(:team, organization: org)
    create(:team_group_mapping, team: team, tenant: tenant)
    Team::GroupMapping.any_instance.expects(:destroy).returns(false)

    assert_no_changes "tenant.status" do
      assert_raises(ActiveRecord::RecordNotDestroyed) do
        tenant.disable
      end
    end
  end

  context "saml settings changed" do
    test "disables tenant when unsupported provider is detected" do
      provider = create(:organization_saml_provider, organization: @org,
                        issuer: "https://fake-invalid-does-not-work.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")
      tenant = @org.team_sync_tenant
      assert_predicate tenant, :enabled?
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        tenant.saml_settings_changed(provider)
        tenant.reload
        assert_predicate tenant, :disabled?
      end
    end

    test "disables tenant when provider type no longer matches" do
      provider = create(:organization_saml_provider, organization: @org,
                        issuer: "http://www.okta.com/exk1alt42ls3GoKdV1d8")
      # @org provider from fixture has type of https://sts.windows.net
      # the provider we was passing in to saml_settings_changed has a type of
      # http://www.okta.com. They will not match and therefore disable the tenant
      tenant = @org.team_sync_tenant
      assert_predicate tenant, :enabled?
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        tenant.saml_settings_changed(provider)
        assert_predicate tenant, :disabled?
      end
    end

    test "disables tenant when provider id no longer matches" do
      provider = create(:organization_saml_provider, organization: @org,
                        issuer: "https://sts.windows.net/b2261f3f-d5fb-4682-b8ed-5cf081a1e841/")
      tenant = @org.team_sync_tenant
      assert_predicate tenant, :enabled?
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        tenant.saml_settings_changed(provider)
        tenant.reload
        assert_predicate tenant, :disabled?
      end
    end

    test "does not change state of an enabled tenant when SAML Provider settings are unchanged" do
      tenant = @org.team_sync_tenant
      assert_predicate tenant, :enabled?
      assert_no_enqueued_jobs(only: UpdateTeamSyncTenantJob) do
        tenant.saml_settings_changed(@saml_provider)
        tenant.reload
        assert_predicate tenant, :enabled?
      end
    end
  end
end if GitHub.team_synchronization_available?
