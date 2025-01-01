# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamSyncSetupFlowTest < GitHub::TestCase
  fixtures do
    @org = create(:business_plus_org, login: "saml-org")

    create :team_sync_tenant, organization: @org, status: "pending"

    @owner = @org.admin

    @business = create(:business, owners: [@owner])

    create :business_team_sync_tenant, business: @business, status: "pending"
  end

  def team_sync_setup_flow(org: @org, business: nil, actor: @owner, client: @client, force: false)
    @team_sync_setup_flow = nil if force
    params = if business
      { business: business }
    else
      { organization: org }
    end
    params.merge!({ actor: actor, service_client: client })
    @team_sync_setup_flow ||= ::TeamSync::SetupFlow.new(**T.unsafe(params))
  end

  context "#initiate_setup" do
    test "registers tenant with org identifier, provider type" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
      end

      team_sync_setup_flow(force: true) # reload

      assert_equal "pending", team_sync_setup_flow.status
      assert_equal "azuread", team_sync_setup_flow.provider_type
      assert_equal "pid", team_sync_setup_flow.provider_id
    end

    test "registers tenant with business identifier, provider type" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow(business: @business).initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
      end

      team_sync_setup_flow(business: @business, force: true) # reload

      assert_equal "pending", team_sync_setup_flow.status
      assert_equal "azuread", team_sync_setup_flow.provider_type
      assert_equal "pid", team_sync_setup_flow.provider_id
    end

    test "registers tenant with ssws token" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "okta", provider_id: "pid", encrypted_ssws_token: "token")
        assert_nil err
      end

      team_sync_setup_flow(force: true) # reload

      assert_equal "pending", team_sync_setup_flow.status
      assert_equal "okta", team_sync_setup_flow.provider_type
      assert_equal "pid", team_sync_setup_flow.provider_id
      assert_equal "token", team_sync_setup_flow.encrypted_ssws_token
    end

    test "registers tenant with url" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "okta", provider_id: "pid", url: "http://example.com")
        assert_nil err
      end

      team_sync_setup_flow(force: true) # reload

      assert_equal "pending", team_sync_setup_flow.status
      assert_equal "okta", team_sync_setup_flow.provider_type
      assert_equal "pid", team_sync_setup_flow.provider_id
      assert_equal "http://example.com", team_sync_setup_flow.url
    end

    test "registers tenant instruments team sync setup initiated" do
      events = subscribe "team_sync_tenant.setup_initiated"
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
      end

      assert event = events.pop, "a team_sync_tenant.setup_initiated event was expected"
      assert_equal "team_sync_tenant.setup_initiated", event.name
    end

    # TODO ^ that for business?

    test "fails unless initial state is unknown or disabled" do
      team_sync_setup_flow.send(:status=, "enabled")
      team_sync_setup_flow(force: true) # reload

      err = team_sync_setup_flow.initiate_setup(provider_type: "azuread", provider_id: "pid")
      assert_equal :invalid_state_transition, err
    end

    test "fails with invalid provider_type" do
      err = team_sync_setup_flow.initiate_setup(provider_type: "unsupported", provider_id: "pid")
      assert_equal :invalid_provider_type, err
    end

    test "triggers automatic app installation for organizations" do
      AutomaticAppInstallation.expects(:trigger).with do |args|
        assert_equal :team_sync_enabled, args[:type]
        assert_equal @org, args[:originator]
        assert_equal @owner, args[:actor]
      end

      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
      end
    end

    test "does not trigger automatic app installation for business" do
      AutomaticAppInstallation.expects(:trigger).never

      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow(business: @business).initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
      end
    end
  end

  context ".callback" do
    test "fails when provider_id does not match" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(
          provider_type: "azuread",
          provider_id: "a3350e2e-d5fb-4682-b8ed-5cf081a1e841",
        )
        assert_nil err
      end

      token = team_sync_setup_flow.send(:generate_token)
      provider_id = "bar"

      flow, err = ::TeamSync::SetupFlow.callback(
        token: token,
        provider_id: provider_id,
        actor: @owner,
      )
      refute_nil err
      assert_equal :invalid_state, err
    end

    test "resumes setup flow when organization provider_id matches" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(
          provider_type: "azuread",
          provider_id: "a3350e2e-d5fb-4682-b8ed-5cf081a1e841",
        )
        assert_nil err
      end

      token = team_sync_setup_flow.send(:generate_token)
      provider_id = team_sync_setup_flow.provider_id

      flow, err = ::TeamSync::SetupFlow.callback(
        token: token,
        provider_id: provider_id,
        actor: @owner,
      )
      assert_nil err
      assert_equal @org, flow.organization
    end

    test "resumes setup flow when business provider_id matches" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow(business: @business).initiate_setup(
          provider_type: "azuread",
          provider_id: "a3350e2e-d5fb-4682-b8ed-5cf081a1e841",
        )
        assert_nil err
      end

      token = team_sync_setup_flow.send(:generate_token)
      provider_id = team_sync_setup_flow.provider_id

      flow, err = ::TeamSync::SetupFlow.callback(
        token: token,
        provider_id: provider_id,
        actor: @owner,
      )
      assert_nil err
      assert_equal @business, flow.business
    end
  end

  context "#setup_callback" do
  end

  context "#approve" do
    test "Does not trigger team sync setup job if target is not a business" do
      flow = team_sync_setup_flow(org: @org)
      flow.status = "ready"
      flow.tenant.stubs(:update)
      flow.tenant.stubs(:register)
      assert_enqueued_jobs 0, only: UpdateTeamSyncForBusinessOrganizationJob do
        flow.approve
      end
    end

    test "Triggers team sync setup job for all orgs if target is a business" do
      flow = team_sync_setup_flow(business: @business)
      flow.status = "ready"
      flow.tenant.stubs(:update)
      flow.tenant.stubs(:register)
      org1 = create(:organization)
      org2 = create(:organization)
      @business.add_organization(org1)
      @business.add_organization(org2)

      assert_enqueued_jobs 2, only: UpdateTeamSyncForBusinessOrganizationJob do
        assert_enqueued_with args: [{ org_id: org1.id }], job: UpdateTeamSyncForBusinessOrganizationJob do
          assert_enqueued_with args: [{ org_id: org2.id }], job: UpdateTeamSyncForBusinessOrganizationJob do
            flow.approve
          end
        end
      end
    end
  end

  context "#disable" do
    test "Does not trigger team sync setup job if target is not a business" do
      flow = team_sync_setup_flow(org: @org)
      flow.status = "enabled"
      flow.tenant.stubs(:disable)
      flow.tenant.stubs(:register)
      assert_enqueued_jobs 0, only: UpdateTeamSyncForBusinessOrganizationJob do
        flow.disable
      end
    end

    test "Triggers team sync setup job for all orgs if target is a business" do
      flow = team_sync_setup_flow(business: @business)
      flow.status = "enabled"
      flow.tenant.stubs(:disable)
      flow.tenant.stubs(:register)
      org1 = create(:organization)
      org2 = create(:organization)
      @business.add_organization(org1)
      @business.add_organization(org2)

      assert_enqueued_jobs 2, only: UpdateTeamSyncForBusinessOrganizationJob do
        assert_enqueued_with args: [{ org_id: org1.id }], job: UpdateTeamSyncForBusinessOrganizationJob do
          assert_enqueued_with args: [{ org_id: org2.id }], job: UpdateTeamSyncForBusinessOrganizationJob do
            flow.disable
          end
        end
      end
    end
  end

  context "#setup_url" do
    test "returns nothing unless tenant is registered with provider type" do
      assert_equal "pending", team_sync_setup_flow.status
      assert_nil team_sync_setup_flow.setup_url(redirect_uri: "test", token: "")
    end

    test "returns setup URL when tenant is registered with provider type" do
      VCR.use_cassette "team-sync/register-pending" do
        err = team_sync_setup_flow.initiate_setup(provider_type: "azuread", provider_id: "pid")
        assert_nil err
        _token, err = team_sync_setup_flow.generate_setup_lease_token
        assert_nil err
      end

      redirect_uri = "satellite-sprints"

      setup_url = team_sync_setup_flow.setup_url(redirect_uri: redirect_uri, token: "abc").to_s
      refute_nil setup_url

      # "https://login.microsoftonline.com/common/adminconsent?client_id=efcf6031-0d59-4349-9475-29cc3e77aa1b&redirect_uri=hi&state=AAAAFywYbV63dNDTGxj9hFcMMNHlDv6Dks5cnZdbgqZvcmdfaWQYrXByb3ZpZGVyX3R5cGWnYXp1cmVhZA%3D%3D"
      assert_match %r{login\.microsoftonline\.com/#{team_sync_setup_flow.provider_id}/adminconsent}, setup_url
      assert_match %r{redirect_uri=#{redirect_uri}}, setup_url
    end
  end
end if GitHub.team_synchronization_available?
