# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanningAlertPayloadSharedMethods
  extend T::Helpers

  ResponseMock = Struct.new(:data, :error)

  requires_ancestor { GitHub::BasicTestCase }

  def shared_fixtures
    @all_secrets = []
    @open_secrets = []
    @resolved_secrets = []
    @reopened_secrets = []
    @revoked_secrets = []

    yield

    @security_manager_team1 = create(:security_manager_team, organization: @org1)
    @security_manager_team1.add_member(@business_owner_security_manager)

    @security_manager_team2 = create(:security_manager_team, organization: @org2)
    @security_manager_team2.add_member(@business_owner_security_manager)

    @repo1 = create :repository, owner: @org1, id: 1
    @repo2 = create :repository, owner: @org2, id: 2

    @rando = create :user, login: "rando"

    @secret_scanning_visible_repos = [@repo1, @repo2]
    resolutions = [:revoked, :wont_fix, :false_positive]
    @secret_scanning_visible_repos.each_with_index do |repo, i|
      example_repo :with_tokens, repo

      # create open token scan result
      token1 = GitHub::TokenScanning::FoundToken.new(type: "STRIPE", token: SecureRandom.hex(32), url: "", report_url: "", path: "foo.txt", commit: SecureRandom.hex(20), blob: "7d7d5bd91e0039acffb385ea92f48ad18d92e788", start_line: 1, end_line: 1, start_column: 10, end_column: 34, content_type: 1)
      secret = TokenScanResult.create_from_found_token!(repo, "STRIPE", token1.token)
      location1 = TokenScanResultLocation.create_from_found_token!(secret, token1)
      secret.resolve!(resolution: :reopened, actor: @business_owner_org_admin)
      secret.update(has_valid_locations: true, first_location_id: location1.id)
      @all_secrets << secret
      @open_secrets << secret

      # create resolved token scan result
      token2 = GitHub::TokenScanning::FoundToken.new(type: "STRIPE", token: SecureRandom.hex(32), url: "", report_url: "", path: "foo.txt", commit: SecureRandom.hex(20), blob: "7d7d5bd91e0039acffb385ea92f48ad18d92e788", start_line: 1, end_line: 1, start_column: 10, end_column: 34, content_type: 1)
      secret = TokenScanResult.create_from_found_token!(repo, "STRIPE", token2.token)
      location2 = TokenScanResultLocation.create_from_found_token!(secret, token2)
      secret.resolve!(resolution: resolutions[i], actor: @business_owner_org_admin, resolution_comment: "comment")
      secret.update(has_valid_locations: true, first_location_id: location2.id)
      @all_secrets << secret
      @resolved_secrets << secret
      if secret.revoked?
        @revoked_secrets << secret
      end

      SecretScanningRepository.create(
        repository_id: repo.id,
        organization_id: repo.owner_id,
        source_updated_at: Time.now.utc,
        feature_visible: true,
      )
    end

    @org_for_second_owner = create(:business_plus_organization, business: @business)
    @second_owner_org_repo = create :repository, owner: @org_for_second_owner, id: 3, from_example: :with_tokens
    @org_for_second_owner.add_admin(@business_owner_org_admin_2)

    # create open token scan result
    token1 = GitHub::TokenScanning::FoundToken.new(type: "STRIPE", token: SecureRandom.hex(32), url: "", report_url: "", path: "foo.txt", commit: SecureRandom.hex(20), blob: "7d7d5bd91e0039acffb385ea92f48ad18d92e788", start_line: 1, end_line: 1, start_column: 10, end_column: 34, content_type: 1)
    @second_owner_secret = TokenScanResult.create_from_found_token!(@second_owner_org_repo, "STRIPE", token1.token)
    @second_owner_secret.publicly_leaked = true
    @second_owner_secret.multi_repo = true
    location = TokenScanResultLocation.create_from_found_token!(@second_owner_secret, token1)
    @second_owner_secret.resolve!(resolution: :reopened, actor: @business_owner_org_admin_2)
    @second_owner_secret.update(has_valid_locations: true, first_location_id: location.id)
    SecretScanningRepository.create(
      repository_id: @second_owner_org_repo.id,
      organization_id: @second_owner_org_repo.owner_id,
      source_updated_at: Time.now.utc,
      feature_visible: true,
      visibility: "private",
    )

    @secret_scanning_enabled_repos = @secret_scanning_visible_repos + [@second_owner_org_repo]

    @all_api_tokens = @all_secrets.map do |s|
      token = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.now.utc,
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "foo.txt"),
        id: s.id,
        label: "Label",
        number: s.number,
        repository_id: s.repository_id,
        slug: "stripe_api_key",
        token_type: s.token_type
      )
      token.resolution = s.resolution.upcase if resolutions.include?(s.resolution.to_sym)
      token
    end
  end

  def shared_setup
    SecurityProduct::AdvancedSecurity.any_instance.stubs(:can_enable?).returns(SecurityProduct::Result.new(true))
    VCR.configure do |c|
      # We are matching on request body, as it contains organization ids
      c.default_cassette_options = { match_requests_on: %i[method uri body] }
    end

    if GitHub.enterprise?
      #@business ||= Business.first
      GitHub::Enterprise.ensure_business!
      @business = GitHub.global_business
      @business.add_owner(@business_owner_org_admin, actor: @business_owner_org_admin)
      @business.add_owner(@business_owner_security_manager, actor: @business_owner_security_manager)
      @business.add_owner(@business_owner_org_admin_2, actor: @business_owner_org_admin_2)
      @org1.update(business: @business)
      @org2.update(business: @business)
      @org_for_second_owner.update(business: @business)
    end

    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    @secret_scanning_enabled_repos.each { |repo| SecretScanning::Features::Repo::TokenScanning.new(repo).enable(actor: @business_owner_org_admin) }
  end

  def self.mock_get_token(resolutions: [], secret: nil, with: nil, bypass: false, bypassed_by: nil, bypass_exemption_request_id: nil)
    mock = GitHub::TokenScanning::Service::Client.any_instance
      .expects(:get_token)
      .once
    hash = {
      created_at: Time.now.utc,
      updated_at: Time.now.utc,
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "foo.txt"),
      id: secret&.id,
      label: "Label",
      number: secret&.number,
      repository_id: secret&.repository_id,
      slug: "stripe_api_key",
      token_type: secret&.token_type,
      validity: secret&.validity,
    }
    if GitHub.flipper.feature(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS).enabled?
      hash[:publicly_leaked] = true
      hash[:multi_repo] = true
    end
    token = GitHub::Proto::SecretScanning::Api::V2::Token.new(hash)

    token.resolution = T.must(secret&.resolution).upcase.to_sym if resolutions.include?(secret&.resolution&.to_sym)
    token.resolution_comment = T.must(secret.resolution_comment) if secret&.resolution_comment
    if bypass
      token.push_protection_bypassed = true
      token.push_protection_bypassed_by_user_id = T.must(bypassed_by&.id)
      token.push_protection_bypassed_at = Google::Protobuf::Timestamp.new(seconds: DateTime.now.to_i)
      token.bypass_exemption_request_id = bypass_exemption_request_id if bypass_exemption_request_id
    else
      token.push_protection_bypassed = false
    end

    mock = mock.with(with) if with
    mock.returns(ResponseMock.new(
      data: GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse.new(
        token: token
      )
    ))
  end
end

module SecretScanningAlertPayloadSharedTest
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(GitHub::TestCase))

    context "Alert Webhook Payload Tests" do
      test "payload for alert created" do

        secret = @open_secrets.first
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
                action: :created,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :created, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
        assert_equal "unknown", alert_payload[:validity]
        refute_nil alert_payload[:created_at]
        refute_nil alert_payload[:updated_at]
        assert_nil alert_payload[:resolution]
        assert_nil alert_payload[:resolved_by]
        assert_nil alert_payload[:resolved_at]
        assert_equal "#{GitHub.api_url}/repos/#{@repo1.name_with_display_owner}/secret-scanning/alerts/#{secret.number}", alert_payload[:url]
        assert_equal "#{GitHub.url}/#{@repo1.name_with_display_owner}/security/secret-scanning/#{secret.number}", alert_payload[:html_url]
        assert_equal "#{GitHub.api_url}/repos/#{@repo1.name_with_display_owner}/secret-scanning/alerts/#{secret.number}/locations", alert_payload[:locations_url]
      end

      test "payload for alert validated" do
        secret = @open_secrets.first
        secret.validity = 1 # set validity to active
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
                action: :validated,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :validated, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
        assert_equal "active", alert_payload[:validity]
        refute_nil alert_payload[:created_at]
        refute_nil alert_payload[:updated_at]
        assert_nil alert_payload[:resolution]
        assert_nil alert_payload[:resolved_by]
        assert_nil alert_payload[:resolved_at]
        assert_equal "#{GitHub.api_url}/repos/#{@repo1.name_with_display_owner}/secret-scanning/alerts/#{secret.number}", alert_payload[:url]
        assert_equal "#{GitHub.url}/#{@repo1.name_with_display_owner}/security/secret-scanning/#{secret.number}", alert_payload[:html_url]
        assert_equal "#{GitHub.api_url}/repos/#{@repo1.name_with_display_owner}/secret-scanning/alerts/#{secret.number}/locations", alert_payload[:locations_url]
      end

      test "payload for alert resolved with wont_fix resolution" do
        secret = @resolved_secrets.last
        SecretScanningAlertPayloadSharedMethods.mock_get_token(resolutions: [:revoked, :wont_fix, :false_positive], secret: secret)

        event_args = {
                action: :resolved,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :resolved, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal secret.resolution, alert_payload[:resolution]
        assert_equal secret.resolution_comment, alert_payload[:resolution_comment]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
        assert_nil alert_payload[:push_protection_bypassed_by]
        assert_nil alert_payload[:push_protection_bypassed_at]
        assert_nil alert_payload[:push_protection_bypass_request_reviewer]
        assert_nil alert_payload[:push_protection_bypass_request_comment]
        assert_nil alert_payload[:push_protection_bypass_request_html_url]
      end

      test "payload for alert revoked" do
        secret = @revoked_secrets.first
        SecretScanningAlertPayloadSharedMethods.mock_get_token(resolutions: [:revoked, :wont_fix, :false_positive], secret: secret)

        event_args = {
                action: :revoked,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :revoked, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.resolution, alert_payload[:resolution]
        assert_equal secret.resolution_comment, alert_payload[:resolution_comment]
        assert_equal secret.number, alert_payload[:number]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
      end

      test "payload for alert reopened" do
        secret = @second_owner_secret
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
          action: :reopened,
          repository_id: @repo1.id,
          alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)
        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :reopened, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
        assert_nil alert_payload[:resolution]
        assert_nil alert_payload[:resolved_at]
        assert_nil alert_payload[:resolved_by]
      end

      test "payload for alert publicly_leaked" do
        secret = @second_owner_secret
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
          action: :publicly_leaked,
          repository_id: @repo1.id,
          alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)
        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :publicly_leaked, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal "stripe_api_key", alert_payload[:secret_type]
        assert_nil alert_payload[:resolution]
        assert_nil alert_payload[:resolved_at]
        assert_nil alert_payload[:resolved_by]
        if GitHub.flipper.feature(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS).enabled?
          assert_equal true, alert_payload[:publicly_leaked]
        else
          assert_nil alert_payload[:publicly_leaked]
        end
      end

      test "payload contains false for bypassed if not bypassed", skip_enterprise: true do
        secret = @open_secrets.first
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
                action: :created,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :created, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal false, alert_payload[:push_protection_bypassed]
        assert_nil alert_payload[:push_protection_bypassed_by]
        assert_nil alert_payload[:push_protection_bypassed_at]
        assert_nil alert_payload[:push_protection_bypass_request_reviewer]
        assert_nil alert_payload[:push_protection_bypass_request_comment]
        assert_nil alert_payload[:push_protection_bypass_request_html_url]
      end

      test "payload contains bypass info if bypassed" do
        secret = @open_secrets.first
        bypass_request = Exemptions::ExemptionRequest.new(id: 1, repository: @repo1, number: 3, requester_comment: "bypass comment")
        bypass_response = Exemptions::ExemptionResponse.new(id: 1, reviewer: @business_owner_security_manager, exemption_request: bypass_request)
        Exemptions::ExemptionResponse.expects(:find_by).with(exemption_request: bypass_request.id).returns(bypass_response)
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret, bypass: true, bypassed_by: @rando, bypass_exemption_request_id: bypass_request.id)

        event_args = {
                action: :created,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :created, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal true, alert_payload[:push_protection_bypassed]
        refute_nil alert_payload[:push_protection_bypassed_by]
        refute_nil alert_payload[:push_protection_bypassed_at]
        assert_equal @business_owner_security_manager.id, alert_payload[:push_protection_bypass_request_reviewer][:id]
        assert_equal "bypass comment", alert_payload[:push_protection_bypass_request_comment]
        assert_equal "#{GitHub.url}/#{@repo1.name_with_display_owner}/secret_scanning/exemptions/#{bypass_request.number}", alert_payload[:push_protection_bypass_request_html_url]
      end

      test "payload does not contain bypass info if not bypassed" do
        secret = @open_secrets.first
        SecretScanningAlertPayloadSharedMethods.mock_get_token(secret: secret)

        event_args = {
                action: :created,
                repository_id: @repo1.id,
                alert_number: secret.number,
        }
        event = Hook::Event::SecretScanningAlertEvent.new(event_args)

        payload = Hook::Payload::SecretScanningAlertPayload.new(event)
        v3 = payload.to_hash

        assert_equal :created, v3[:action]

        alert_payload = v3[:alert]

        assert_equal secret.number, alert_payload[:number]
        assert_equal false, alert_payload[:push_protection_bypassed]
        assert_nil alert_payload[:push_protection_bypassed_by]
        assert_nil alert_payload[:push_protection_bypassed_at]
        assert_nil alert_payload[:push_protection_bypass_request_reviewer]
        assert_nil alert_payload[:push_protection_bypass_request_comment]
        assert_nil alert_payload[:push_protection_bypass_request_html_url]
      end
    end
  end
end

class SecretScanningAlertPayloadTest < GitHub::TestCase
  include SecretScanningAlertPayloadSharedMethods
  include SecretScanningAlertPayloadSharedTest

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    shared_fixtures do
      @business_owner_org_admin = create(:user, business: @business, login: "business-owner")
      @business_owner_org_admin_2 = create(:user, business: @business, login: "business-owner-2")
      @business_owner_security_manager = create(:user, business: @business, login: "business-owner-security-manager")
      @org_admin = create(:user, login: "org-owner")

      unless GitHub.enterprise?
        @business = create :business,  owners: [@business_owner_org_admin, @business_owner_org_admin_2, @business_owner_security_manager]
      end

      @member = create :user, login: "member"

      @org1 = create(:business_plus_organization, business: @business)
      @org1.add_admin(@business_owner_org_admin)
      @org1.add_admin(@org_admin)
      @org1.add_member @member, action: :write
      @org2 = create(:business_plus_organization, business: @business)
      @org2.add_admin(@business_owner_org_admin)
      @org2.add_admin(@org_admin)
      @org2.add_member @member, action: :write
    end
  end

  setup do
    shared_setup
  end
end

class SecretScanningAlertPayloadMultiTenantTest < GitHub::TestCase
  include SecretScanningAlertPayloadSharedMethods
  include SecretScanningAlertPayloadSharedTest

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    on_multi_tenant_enterprise do
      @business = create :business, :enterprise_managed
      shared_fixtures do
        @business_owner_org_admin = create(:emu, :owner, business: @business, login: "business-owner")
        @business_owner_org_admin_2 = create(:emu, :owner, business: @business, login: "business-owner-2")
        @business_owner_security_manager = create(:emu, :owner, business: @business, login: "business-owner-security-manager")

        @org1 = create(:organization, business: @business)
        @org2 = create(:organization, business: @business)
      end
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
    shared_setup
  end
end unless GitHub.single_business_environment?
