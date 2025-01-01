# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamSyncBusinessTenantTest < GitHub::TestCase
  include HydroTestHelpers
  extend EncryptedColumnTestHelper

  FEATURE_FLAG = "encrypt_as_plaintext_team_sync_business_tenant_encrypted_ssws_token".freeze
  test_encrypted_column(:business_team_sync_tenant, :encrypted_ssws_token, feature_flag: FEATURE_FLAG)

  fixtures do
    @business = create(:business)
    @saml_provider = create(:business_saml_provider, business: @business, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")

    create :business_team_sync_tenant, business: @business
  end

  test "invalid status throws an error" do
    tenant = @business.team_sync_tenant

    assert_raises ArgumentError do
      tenant.status = "blargh"
    end
  end

  test "setting an invalid provider type throws an error" do
    tenant = @business.team_sync_tenant

    assert_raises ArgumentError do
      tenant.provider_type = "blargh"
    end
  end

  test "team sync enabled for tenant?" do
    tenant = @business.team_sync_tenant
    assert_predicate tenant, :team_sync_enabled?
  end

  test "destroy removes the tenant" do
    tenant = @business.team_sync_tenant
    assert_equal "enabled", tenant.status
    tenant.destroy
    assert_nil @business.reload.team_sync_tenant
  end

  context "instrumentation emits event to GlobalInstrumenter" do
    test "when status changes to enabled" do
      tenant = create :business_team_sync_tenant, status: "ready"
      GlobalInstrumenter.expects(:instrument).with(
        "team_sync_tenant.status_change",
        team_sync_business_tenant: tenant,
        business: tenant.business,
        previous_status: "ready",
        current_status: "enabled",
      )
      tenant.update(status: "enabled")
    end

    test "when status changes to disabled" do
      tenant = create :business_team_sync_tenant, status: "enabled"
      GlobalInstrumenter.expects(:instrument).with(
        "team_sync_tenant.status_change",
        team_sync_business_tenant: tenant,
        business: tenant.business,
        previous_status: "enabled",
        current_status: "disabled",
      )
      tenant.disable
    end

    test "when okta credentials are updated" do
      tenant = create :team_sync_tenant
      events = subscribe "team_sync_tenant.update_okta_credentials"

      tenant.update(encrypted_ssws_token: "new token", url: "https://www.updated.com")

      assert event = events.pop, "a team_sync_tenant.update_okta_credentials event was expected"
      assert_equal "team_sync_tenant.update_okta_credentials", event.name
    end
  end

  test "disable cascades to orgs (disables their tenants and remove their mappings)" do
    org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
    @business.add_organization(org)
    org_tenant = create(:team_sync_tenant, organization: org)
    team = create(:team, organization: org)
    mapping = create(:team_group_mapping, team: team, tenant: org_tenant)

    assert_predicate @business.team_sync_tenant, :enabled?
    assert_predicate org_tenant, :enabled?
    assert_difference -> { org_tenant.team_group_mappings.count }, -1 do
      @business.team_sync_tenant.disable
    end
    assert_predicate @business.team_sync_tenant, :disabled?
    assert_predicate org_tenant.reload, :disabled?
  end

  test "#disable does not change status if tenant disablement fails" do
    org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
    @business.add_organization(org)
    org_tenant = create(:team_sync_tenant, organization: org)
    team = create(:team, organization: org)
    mapping = create(:team_group_mapping, team: team, tenant: org_tenant)
    TeamSync::Tenant.any_instance.expects(:disable).raises(ActiveRecord::RecordNotDestroyed)

    assert_no_changes "@business.team_sync_tenant.status" do
      assert_raises(ActiveRecord::RecordNotDestroyed) do
        @business.team_sync_tenant.disable
      end
    end
  end

  test "register sets the setup_url_tempate (by registering a group-syncer tenant for the business)" do
    tenant = @business.team_sync_tenant
    GroupSyncer.client.expects(:register_tenant)
                      .with(
                        org_id: @business.global_relay_id,
                        external_provider_type: 1,
                        external_provider_id: tenant.provider_id,
                        status: 4,
                        token: tenant.encrypted_ssws_token,
                        url: tenant.url,
                      )
                      .returns(Twirp::ClientResp.new(
                        data: GroupSyncer::V1::RegisterTenantResponse.new(
                          setup_url: "some_url"
                        ),
                        error: nil))

    tenant.register
    assert_equal "some_url", tenant.setup_url_template
  end

  context "saml settings changed" do
    test "disables tenant when unsupported provider is detected" do
      provider = create(:business_saml_provider, business: @business,
                        issuer: "https://fake-invalid-does-not-work.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")
      tenant = @business.team_sync_tenant
      assert_predicate tenant, :enabled?
      tenant.saml_settings_changed(provider)
      tenant.reload
      assert_predicate tenant, :disabled?
    end

    test "disables tenant when provider type no longer matches" do
      provider = create(:business_saml_provider, business: @business,
                        issuer: "http://www.okta.com/exk1alt42ls3GoKdV1d8")
      # @org provider from fixture has type of https://sts.windows.net
      # the provider we was passing in to saml_settings_changed has a type of
      # http://www.okta.com. They will not match and therefore disable the tenant
      tenant = @business.team_sync_tenant
      assert_predicate tenant, :enabled?
      tenant.saml_settings_changed(provider)
      assert_predicate tenant, :disabled?
    end

    test "disables tenant when provider id no longer matches" do
      provider = create(:business_saml_provider, business: @business,
                        issuer: "https://sts.windows.net/b2261f3f-d5fb-4682-b8ed-5cf081a1e841/")
      tenant = @business.team_sync_tenant
      assert_predicate tenant, :enabled?
      tenant.saml_settings_changed(provider)
      tenant.reload
      assert_predicate tenant, :disabled?
    end

    test "does not change state of an enabled tenant when SAML Provider settings are unchanged" do
      tenant = @business.team_sync_tenant
      assert_predicate tenant, :enabled?
      tenant.saml_settings_changed(@saml_provider)
      tenant.reload
      assert_predicate tenant, :enabled?
    end
  end
end if GitHub.team_synchronization_available?
