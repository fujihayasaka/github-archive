# coding: utf-8
# typed: true
# frozen_string_literal: true

# rubocop:disable Style/HashSyntax

require "test_helper"

class PushProtectionServiceTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @org = create(:business_plus_organization, business: @business)
    @org_owned_repo = create(:repository, owner: @org)
    @org.add_member(@user)

    @owner = create :paid_user, login: "octocat"

    @team = create(:team, organization: @org, privacy: :closed)
  end

  context "scan_content" do
    test "successful scan request" do
      partner_metadata = stub(
        token_type: "GITHUB_TOKEN_V2",
        label: "GitHub Personal Access Token",
        slug: "github_token_v2",
        provider: "GitHub",
      )
      custom_pattern_metadata = stub(
        token_type: "cp_1234",
        label: "My custom pattern",
        slug: "my_custom_pattern",
        provider: "CUSTOM_PATTERN",
      )

      secrets = [
        stub(:type => "GITHUB_TOKEN_V2", :token_metadata => partner_metadata, :fingerprint => "abcd1234", bypass_placeholder_ksuid: "1", :locations => [
          stub(:path => nil,
               :commit_oid => nil,
               :blob_oid => nil,
               :start_line => 1,
               :end_line => 1,
               :start_line_byte_position => 2,
               :end_line_byte_position => 10
              ),
        ]),
        stub(:type => "cp_1234", :token_metadata => custom_pattern_metadata, :fingerprint => "abcd4567", bypass_placeholder_ksuid: "2", :locations => [
          stub(:path => nil,
               :commit_oid => nil,
               :blob_oid => nil,
               :start_line => 2,
               :end_line => 2,
               :start_line_byte_position => 5,
               :end_line_byte_position => 20
              ),
        ]),
      ]
      secrets[0].stubs(:is_a?).with(GitHub::Proto::SecretScanning::Scans::V2::Secret).returns(true)
      secrets[1].stubs(:is_a?).with(GitHub::Proto::SecretScanning::Scans::V2::Secret).returns(true)

      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::ScanBytesResponse.new)
      data.stubs(:completed).returns(true)
      data.stubs(:secrets).returns(secrets)
      data.stubs(:num_secrets_found_over_limit).returns(5)
      data.stubs(:used_delegated_bypass_request_ids).returns([])
      scan_response = stub(:data => data, :error => nil)

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(scan_response)

      result = SecretScanning::Services::PushProtectionService.scan_content("Hello World", @repo, @user, "path/to/secrets.txt")

      assert result != nil
      assert_equal true, result.completed
      assert_equal 5, result.num_secrets_found_over_limit
      assert_equal 2, result.secrets.length
      assert_equal "GITHUB_TOKEN_V2", result.secrets[0]&.type
      assert_equal "GITHUB_TOKEN_V2", result.secrets[0]&.token_metadata&.token_type
      assert_equal "github_token_v2", result.secrets[0]&.token_metadata&.slug
      assert_equal "GitHub Personal Access Token", result.secrets[0]&.token_metadata&.label
      locations = T::must(result.secrets[0]&.locations)
      assert_equal 1, locations.length
      assert_equal 1, locations[0]&.start_line
      assert_equal 1, locations[0]&.end_line
      assert_equal 2, locations[0]&.start_line_byte_position
      assert_equal 10, locations[0]&.end_line_byte_position
      assert_equal "GitHub", result.secrets[0]&.token_metadata&.provider
      assert_equal "cp_1234", result.secrets[1]&.type
      assert_equal "cp_1234", result.secrets[1]&.token_metadata&.token_type
      assert_equal "my_custom_pattern", result.secrets[1]&.token_metadata&.slug
      assert_equal "My custom pattern", result.secrets[1]&.token_metadata&.label
      assert_equal "CUSTOM_PATTERN", result.secrets[1]&.token_metadata&.provider
      locations = T::must(result.secrets[1]&.locations)
      assert_equal 1, locations.length
      assert_equal 2, locations[0]&.start_line
      assert_equal 2, locations[0]&.end_line
      assert_equal 5, locations[0]&.start_line_byte_position
      assert_equal 20, locations[0]&.end_line_byte_position
    end

    test "fails open when Scan response is nil" do
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(nil)

      result = SecretScanning::Services::PushProtectionService.scan_content("Hello World", @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "fails open when Scan error response" do
      scan_response = stub(:error => "Internal Server Error")
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(scan_response)

      result = SecretScanning::Services::PushProtectionService.scan_content("Hello World", @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "fails open when Scan errors in dotcom" do
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).raises(RuntimeError)

      result = SecretScanning::Services::PushProtectionService.scan_content("Hello World", @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "includes business_id for EMU-owned repository", skip_enterprise: true do
      emu_user = create(:emu)
      emu_user_owned_repo = create(:private_repository, owner: emu_user)

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(nil).with do |request|
        request = T::let(request, GitHub::Proto::SecretScanning::Scans::V2::ScanBytesRequest)
        assert_equal request.repository&.id, emu_user_owned_repo.id
        assert_equal request.actor_id, emu_user.id
        assert_equal request.business_id, emu_user.enterprise_managed_business.id
        refute_equal request.business_id, 0
        refute_nil request.business_id
      end

      SecretScanning::Services::PushProtectionService.scan_content("Hello World", emu_user_owned_repo, emu_user)
    end

    test "includes delegated bypass requests in the request, if delegated bypass is enabled" do
      reviewer = create_bypass_reviewer
      exemption_resource_owner = RuleEngine::RuleSuite.create!(repository: @org_owned_repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
      expected_exemption_requests = [
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 1),
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 2)
      ]
      # Create an unused rejected bypass request - it should be excluded
      create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:rejected], exemption_resource_owner, reviewer, 3)
      # Create a bypass request that was cancelled after it was approved. It should be excluded
      create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 3, request_status: :cancelled)

      expected_delegated_bypass_requests = expected_exemption_requests.map do |exemption_request|
        GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest.new(
          placeholder_ksuid: exemption_request.resource_identifier,
          exemption_request_id: exemption_request.id,
          expires_at: Google::Protobuf::Timestamp.new(seconds: exemption_request.expires_at.to_i),
          reason: GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_FALSE_POSITIVE
        )
      end

      content = "Hello World"
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(nil).with do |request|
        request = T::let(request, GitHub::Proto::SecretScanning::Scans::V2::ScanBytesRequest)
        assert_same_elements request.delegated_bypass_requests, expected_delegated_bypass_requests
        assert_equal request.repository&.id, @org_owned_repo.id
        assert_equal request.actor_id, @user.id
        assert_equal request.content, content
      end

      SecretScanning::Services::PushProtectionService.scan_content(content, @org_owned_repo, @user, delegated_bypass_enabled: true)
    end

    test "includes used delegated bypass request IDs in the response, if returned from TSS" do
      exemption_resource_owner = RuleEngine::RuleSuite.create!(repository: @org_owned_repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
      reviewer = create_bypass_reviewer
      used_exemption_requests = [
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 1),
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 2),
      ]
      used_exemption_request_ids = used_exemption_requests.map(&:id)

      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::ScanPushResponse.new)
      data.stubs(:num_secrets_found_over_limit).returns(0)
      data.stubs(:completed).returns(true)
      data.stubs(:secrets).returns([])
      data.stubs(:used_delegated_bypass_request_ids).returns(used_exemption_request_ids)
      scan_response = stub(:data => data, :error => nil)

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_bytes).returns(scan_response)
      result = SecretScanning::Services::PushProtectionService.scan_content("Hello World", @org_owned_repo, @user, delegated_bypass_enabled: true)
      assert result.completed
      assert_equal used_exemption_request_ids, result.used_delegated_bypass_request_ids
    end
  end

  context "scan_ref_updates" do
    test "successful scan request" do
      ref_updates = [
        Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
        ),
        # unicode characters in refname to make handle https://github.com/github/secret-scanning/issues/3786
        Git::Ref::Update.new(
          repository: @repo,
          refname: "ȑéḟṣ/Ħěąɖs/ṁäÎɲ",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c27",
        )
      ]

      partner_metadata = stub(
        token_type: "GITHUB_TOKEN_V2",
        label: "GitHub Personal Access Token",
        slug: "github_token_v2",
        provider: "GitHub",
      )
      custom_pattern_metadata = stub(
        token_type: "cp_1234",
        label: "My custom pattern",
        slug: "my_custom_pattern",
        provider: "CUSTOM_PATTERN"
      )

      secrets = [
        stub(:type => "GITHUB_TOKEN_V2", :token_metadata => partner_metadata, :fingerprint => "abcd1234", bypass_placeholder_ksuid: "1", :locations => [
          stub(:path => nil,
               :commit_oid => nil,
               :blob_oid => nil,
               :start_line => 1,
               :end_line => 1,
               :start_line_byte_position => 2,
               :end_line_byte_position => 10
              ),
        ]),
        stub(:type => "cp_1234", :token_metadata => custom_pattern_metadata, :fingerprint => "abcd4567", bypass_placeholder_ksuid: "2", :locations => [
          stub(:path => nil,
               :commit_oid => nil,
               :blob_oid => nil,
               :start_line => 2,
               :end_line => 2,
               :start_line_byte_position => 5,
               :end_line_byte_position => 20
              ),
        ]),
      ]
      secrets[0].stubs(:is_a?).with(GitHub::Proto::SecretScanning::Scans::V2::Secret).returns(true)
      secrets[1].stubs(:is_a?).with(GitHub::Proto::SecretScanning::Scans::V2::Secret).returns(true)

      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::ScanPushResponse.new)
      data.stubs(:num_secrets_found_over_limit).returns(5)
      data.stubs(:completed).returns(true)
      data.stubs(:secrets).returns(secrets)
      data.stubs(:used_delegated_bypass_request_ids).returns([])
      scan_response = stub(:data => data, :error => nil)

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(scan_response)

      result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @repo, @user)

      assert result != nil
      assert_equal true, result.completed
      assert_equal 5, result.num_secrets_found_over_limit
      assert_equal 2, result.secrets.length
      assert_equal "GITHUB_TOKEN_V2", result.secrets[0]&.type
      assert_equal "GITHUB_TOKEN_V2", result.secrets[0]&.token_metadata&.token_type
      assert_equal "github_token_v2", result.secrets[0]&.token_metadata&.slug
      assert_equal "GitHub Personal Access Token", result.secrets[0]&.token_metadata&.label
      locations = T::must(result.secrets[0]&.locations)
      assert_equal 1, locations.length
      assert_equal 1, locations[0]&.start_line
      assert_equal 1, locations[0]&.end_line
      assert_equal 2, locations[0]&.start_line_byte_position
      assert_equal 10, locations[0]&.end_line_byte_position
      assert_equal "GitHub", result.secrets[0]&.token_metadata&.provider
      assert_equal "cp_1234", result.secrets[1]&.type
      assert_equal "cp_1234", result.secrets[1]&.token_metadata&.token_type
      assert_equal "my_custom_pattern", result.secrets[1]&.token_metadata&.slug
      assert_equal "My custom pattern", result.secrets[1]&.token_metadata&.label
      assert_equal "CUSTOM_PATTERN", result.secrets[1]&.token_metadata&.provider
      locations = T::must(result.secrets[1]&.locations)
      assert_equal 1, locations.length
      assert_equal 2, locations[0]&.start_line
      assert_equal 2, locations[0]&.end_line
      assert_equal 5, locations[0]&.start_line_byte_position
      assert_equal 20, locations[0]&.end_line_byte_position
    end

    test "fails open when Scan response is nil" do
      ref_updates = [
        Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "a" * 40,
        )
      ]

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(nil)

      result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "fails open when Scan error response" do
      ref_updates = [
        Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "a" * 40,
        )
      ]

      scan_response = stub(:error => "Internal Server Error")
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(scan_response)

      result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "fails open when Scan errors in dotcom" do
      ref_updates = [
        Git::Ref::Update.new(
          repository: @repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "a" * 40,
        )
      ]

      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).raises(RuntimeError)

      result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @repo, @user)

      assert result != nil
      assert_equal 0, result.secrets.length
      assert_equal false, result.completed
    end

    test "includes business_id for EMU-owned repository", skip_enterprise: true do
      emu_user = create(:emu)
      emu_user_owned_repo = create(:private_repository, owner: emu_user)

      ref_updates = [
        Git::Ref::Update.new(
          repository: @org_owned_repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
        )
      ]
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(nil).with do |request|
        request = T::let(request, GitHub::Proto::SecretScanning::Scans::V2::ScanPushRequest)
        assert_equal request.repository&.id, emu_user_owned_repo.id
        assert_equal request.actor_id, emu_user.id
        assert_equal request.business_id, emu_user.enterprise_managed_business.id
        refute_equal request.business_id, 0
        refute_nil request.business_id
      end
      SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, emu_user_owned_repo, emu_user)
    end

    test "includes delegated bypass requests in the request, if delegated bypass is enabled" do
      reviewer = create_bypass_reviewer
      exemption_resource_owner = RuleEngine::RuleSuite.create!(repository: @org_owned_repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
      expected_exemption_requests = [
              create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 1),
             create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 2)
      ]
      # Create an unused rejected bypass request - it should be excluded
      create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:rejected], exemption_resource_owner, reviewer, 3)
      # Create a bypass request that was cancelled after it was approved. It should be excluded
      create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 3, request_status: :cancelled)


      expected_delegated_bypass_requests = expected_exemption_requests.map do |exemption_request|
        GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest.new(
          placeholder_ksuid: exemption_request.resource_identifier,
          exemption_request_id: exemption_request.id,
          expires_at: Google::Protobuf::Timestamp.new(seconds: exemption_request.expires_at.to_i),
          reason: GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_FALSE_POSITIVE
        )
      end

      ref_updates = [
        Git::Ref::Update.new(
          repository: @org_owned_repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
        ),
        # unicode characters in refname to make handle https://github.com/github/secret-scanning/issues/3786
        Git::Ref::Update.new(
          repository: @org_owned_repo,
          refname: "ȑéḟṣ/Ħěąɖs/ṁäÎɲ",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c27",
        )
      ]
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(nil).with do |request|
        request = T::let(request, GitHub::Proto::SecretScanning::Scans::V2::ScanPushRequest)
        assert_same_elements request.delegated_bypass_requests, expected_delegated_bypass_requests
        assert_equal request.repository&.id, @org_owned_repo.id
        assert_equal request.actor_id, @user.id
        assert_equal request.reference_updates.size, 2
      end
      SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @org_owned_repo, @user, delegated_bypass_enabled: true)
    end

    test "includes used delegated bypass request IDs in the response, if returned from TSS" do
      exemption_resource_owner = RuleEngine::RuleSuite.create!(repository: @org_owned_repo, ref_name: "refs/heads/main", before_oid: "before", after_oid: "after", actor: @user)
      reviewer = create_bypass_reviewer
      used_exemption_requests = [
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 1),
        create_exemption_request_and_response(Exemptions::ExemptionResponse::STATUSES[:approved], exemption_resource_owner, reviewer, 2),
      ]
      used_exemption_request_ids = used_exemption_requests.map(&:id)

      data = mock("data")
      data.responds_like(GitHub::Proto::SecretScanning::Scans::V2::ScanPushResponse.new)
      data.stubs(:num_secrets_found_over_limit).returns(0)
      data.stubs(:completed).returns(true)
      data.stubs(:secrets).returns([])
      data.stubs(:used_delegated_bypass_request_ids).returns(used_exemption_request_ids)
      scan_response = stub(:data => data, :error => nil)
      ref_updates = [
        Git::Ref::Update.new(
          repository: @org_owned_repo,
          refname: "refs/heads/main",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
        ),
        # unicode characters in refname to make handle https://github.com/github/secret-scanning/issues/3786
        Git::Ref::Update.new(
          repository: @org_owned_repo,
          refname: "ȑéḟṣ/Ħěąɖs/ṁäÎɲ",
          before_oid: GitHub::NULL_OID,
          after_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c27",
        )
      ]
      GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:scan_push).returns(scan_response)
      result = SecretScanning::Services::PushProtectionService.scan_ref_updates(ref_updates, @org_owned_repo, @user, delegated_bypass_enabled: true)
      assert result.completed
      assert_equal used_exemption_request_ids, result.used_delegated_bypass_request_ids
    end
  end

  context "promote_bypass" do
    test "returns true on a successful request" do
      response = Twirp::ClientResp.new(
        error: nil,
        data: GitHub::Proto::SecretScanning::Scans::V1::PromoteBypassResponse.new(
          bypass: GitHub::Proto::SecretScanning::Scans::V1::Bypass.new(
            expire_at: Time.now.utc,
            reason: GitHub::Proto::SecretScanning::Scans::V1::BypassReason::USED_IN_TESTS,
            token_type: :mailchimp_api_key,
          ),
        ),
      )
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:promote_bypass).returns(response)

      result, error_message = SecretScanning::Services::PushProtectionService.promote_bypass("false_positive", @repo, @user, "1")
      refute_nil result
      assert_nil error_message
    end

    test "returns false on a nil response with an error message" do
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:promote_bypass).returns(nil)

      result, error_message = SecretScanning::Services::PushProtectionService.promote_bypass("false_positive", @repo, @user, "1")
      assert_nil result
      assert_equal "An error has occurred while allowing the secret.", error_message
    end

    test "returns false on an error with an error message" do
      response = Twirp::ClientResp.new(
        error: Twirp::Error.internal("Internal Server Error")
      )
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:promote_bypass).returns(response)

      result, error_message = SecretScanning::Services::PushProtectionService.promote_bypass("false_positive", @repo, @user, "1")
      assert_nil result
      assert_equal "Internal Server Error", error_message
    end

    test "bypass_placeholder_not_found returns true when error message is bypass placeholder not found" do
      response = Twirp::ClientResp.new(
        error: Twirp::Error.internal("bypass placeholder not found")
      )
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:promote_bypass).returns(response)

      result, error_message = SecretScanning::Services::PushProtectionService.promote_bypass("false_positive", @repo, @user, "1")
      assert_nil result
      assert_equal "bypass placeholder not found", error_message
      assert SecretScanning::Services::PushProtectionService.bypass_placeholder_not_found?(error_message)
    end
  end

  context "allow_secret" do
    test "returns true on successful request" do
      response = Twirp::ClientResp.new(
        error: nil,
        data: GitHub::Proto::SecretScanning::Scans::V1::AddBypassResponse.new(
          bypass: GitHub::Proto::SecretScanning::Scans::V1::Bypass.new(id: 1234),
        )
      )
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:add_bypass).returns(response)

      result = SecretScanning::Services::PushProtectionService.allow_secret("GITHUB_TOKEN_V2", "abcd1234", "false_positive", @repo, @user)
      assert_equal true, result
    end

    test "returns false on nil response" do
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:add_bypass).returns(nil)

      result = SecretScanning::Services::PushProtectionService.allow_secret("GITHUB_TOKEN_V2", "abcd1234", "false_positive", @repo, @user)
      assert_equal false, result
    end

    test "returns false on error response" do
      response = Twirp::ClientResp.new(
        error: Twirp::Error.internal("Internal Server Error")
      )
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:add_bypass).returns(response)

      result = SecretScanning::Services::PushProtectionService.allow_secret("GITHUB_TOKEN_V2", "abcd1234", "false_positive", @repo, @user)
      assert_equal false, result
    end
  end

  context "get_bypass_placeholder" do
    test "returns nil on an error response" do
      response = Twirp::ClientResp.new(
        error: Twirp::Error.internal("Internal Server Error")
      )

      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:get_bypass_placeholder).returns(response)

      result, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(@repo, @user, "1")
      assert_nil result
      assert_equal "Internal Server Error", error_message
    end

    test "returns a placeholder on successful request" do
      placeholder = GitHub::Proto::SecretScanning::Scans::V1::BypassPlaceholder.new(
        id: 1,
        created_at: Google::Protobuf::Timestamp.new,
        signature: "abcd1234",
        token_type: "GITHUB_TOKEN_V2",
        owner_id: 1,
        owner_scope: :REPOSITORY_SCOPE,
        ksuid: "1")
      placeholder_response = GitHub::Proto::SecretScanning::Scans::V1::GetBypassPlaceholderResponse.new(placeholder: placeholder)
      placeholder_response.stubs(:data).returns(placeholder)
      response = stub(:error => nil, :data => placeholder_response)
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:get_bypass_placeholder).returns(response)

      result, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(@repo, @user, "1")
      refute_nil result
      assert_nil error_message
    end

    test "returns nil on nil response" do
      GitHub::Proto::SecretScanning::Scans::V1::ScansAPIClient.any_instance.expects(:get_bypass_placeholder).returns(nil)

      result, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(@repo, @user, "1")
      assert_nil result
      assert_equal "An error has occurred while attempting to retrieve the bypass.", error_message
    end
  end

  context "get_custom_message" do
    test "returns nil if no custom message is set" do
      assert_nil SecretScanning::Services::PushProtectionService.get_custom_message(org_repo)
    end

    test "returns business message, then org message even if business one exists" do
      SecretScanning::Features::Org::PushProtection.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Org::PushProtection.new(@org).enable_custom_message(actor: @user)
      SecretScanning::Features::Business::PushProtection.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Business::PushProtection.new(@business).enable_custom_message(actor: @user)

      biz_msg = "biz msg"
      org_repo.business&.set_push_protection_custom_message(biz_msg, @user)
      actual_data = T.must(SecretScanning::Services::PushProtectionService.get_custom_message(org_repo))
      assert_equal "enterprise", actual_data.owner_type
      assert_equal @business.name, actual_data.owner_name
      assert_equal biz_msg, actual_data.message

      org_msg = "org msg"
      org_repo.organization&.set_push_protection_custom_message(org_msg, @user)
      actual_data = T.must(SecretScanning::Services::PushProtectionService.get_custom_message(org_repo))
      assert_equal "organization", actual_data.owner_type
      assert_equal @org.name, actual_data.owner_name
      assert_equal org_msg, actual_data.message
    end
  end

  private

  def create_exemption_request_and_response(response_status, resource_owner, reviewer, identifier, request_status: :pending)
    exemption_request = Exemptions::Public.create_request(
      resource_owner: resource_owner,
      requester: @user,
      resource_identifier: "ksuid" + identifier.to_s,
      repository: @org_owned_repo,
      request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
      requester_comment: "a comment",
      expires_at: (Time.now + 1.day),
    )
    exemption_request.metadata = { reason: "false_positive" }
    exemption_request.status = request_status
    exemption_request.save!
    exemption_response = Exemptions::ExemptionResponse.create!(
      exemption_request: exemption_request,
      reviewer: reviewer,
      status: response_status,
    )
    exemption_request
  end

  def create_bypass_reviewer
    reviewer = create(:user)
    @team.add_member(reviewer)
    @team.add_repository(@org_owned_repo, :admin)
    response = Twirp::ClientResp.new(
      data: GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse.new(
        bypass_reviewers: [GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer.new(
          id: 1,
          owner_id: @org_owned_repo.id,
          owner_scope: :REPOSITORY_SCOPE,
          reviewer_id: @team.id,
          reviewer_type: :TEAM
        )]
      )
    )
    GitHub::Proto::SecretScanning::Scans::V2::ScansAPIClient.any_instance.expects(:get_bypass_reviewers).returns(response).at_least_once
    reviewer
  end

  sig { returns(Repository) }
  def org_repo
    @org_owned_repo
  end

end
