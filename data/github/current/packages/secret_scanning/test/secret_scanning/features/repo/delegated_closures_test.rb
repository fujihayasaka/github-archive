# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Features::Repo
  class RepoDelegatedClosuresTest < GitHub::TestCase
    include SecretScanning::Features::FeatureFlagHelper
    include FineGrainedPermissionsTestHelper

    setup do
      @business = create(:business)
      @business.stubs(:advanced_security_purchased?).returns(true)
      @org = create(:business_plus_org, business: @business)
      @user = create(:user)
      @repo = create(:repository, owner: @org)
      @delegated_closures_repo = SecretScanning::Features::Repo::DelegatedClosures.new(@repo)

      @repo.owner.stubs(:advanced_security_purchased?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)

      @repo.add_member(@user)
      grant_custom_role(user: @user, target: @repo, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])
      @reviewer = create(:user)
      @repo.add_member(@reviewer)
      grant_custom_org_role(user: @reviewer, target: @org, fgps: [:org_review_and_manage_secret_scanning_closure_requests])

      @alert = SecretScanning::Models::Alert.new(
        repository_id: @repo.id,
        number: 1,
        label: "label",
        token_type: "token_type",
        created_at: Time.now,
        # is_closed is all we care about here
        is_closed: true,
        token_type_provider: "token_type_provider",
        validation_support: SecretScanning::Models::ValidationSupport.new(validity_checks_supported: false, on_demand_checks_supported: false),
        low_confidence: false,
        llm_detected: false,
        token_groups: [],
        validity: 1,
        async_check_in_progress: false,
        is_multipart: false,
        slug: "slug",
        is_classic_or_fine_grained_pat: false,
        first_location_in_actions_file: false,
        publicly_leaked: false,
        is_reported: false,
      )
    end

    context "initialize" do
      test "good input" do
        refute_nil @delegated_closures_repo
      end
    end

    context "feature_available?" do
      test "returns false if the repo does not have token scanning available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
        refute @delegated_closures_repo.feature_available?
      end

      test "returns false for repos in free orgs without GHAS purchased" do
        GitHub::Enterprise.license.stubs(:secret_protection_enabled).returns(false)
        free_org = create(:organization)
        free_org.stubs(:advanced_security_purchased?).returns(false)
        free_repo = create(:repository, owner: free_org)
        refute SecretScanning::Features::Repo::DelegatedClosures.new(free_repo).feature_available?
      end

      test "returns true if the repo's org has purchased GHAS" do
        assert @delegated_closures_repo.feature_available?
      end

      test "returns false if sku split is enabled and GHAS/secret scanning license is not available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        @org.stubs(:advanced_security_purchased?).returns(false)
        @org.stubs(:secret_protection_purchased?).returns(false)
        refute @delegated_closures_repo.feature_available?
      end

      test "returns true if sku split is enabled and secret scanning license is available" do
        SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        @org.stubs(:secret_protection_purchased?).returns(true)
        assert @delegated_closures_repo.feature_available?
      end
    end

    context "enabled?" do
      test "returns false if feature isn't available" do
        @delegated_closures_repo.stubs(:feature_available?).returns(false)
        @delegated_closures_repo.enable(actor: @user)
        refute @delegated_closures_repo.enabled?
      end

      test "returns repo feature enablement status" do
        @delegated_closures_repo.enable(actor: @user)
        assert @delegated_closures_repo.feature_available?
        assert @delegated_closures_repo.enabled?
        @delegated_closures_repo.disable(actor: @user)
        refute @delegated_closures_repo.enabled?
      end
    end

    context "display_review_buttons_for_closure_request?" do
      test "returns false if the feature isn't enabled" do
        @delegated_closures_repo.stubs(:enabled?).returns(false)
        refute @delegated_closures_repo.display_review_buttons_for_closure_request?(@reviewer, create_closure_request, @alert)
      end

      test "returns false if the closure request has been approved or rejected" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        closure_request = create_closure_request
        Exemptions::ExemptionResponse.approve!(closure_request, @reviewer)
        refute @delegated_closures_repo.display_review_buttons_for_closure_request?(@reviewer, closure_request.reload, @alert)
      end

      test "returns false if the user doesn't have review permissions" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        refute @delegated_closures_repo.display_review_buttons_for_closure_request?(@user, create_closure_request, @alert)
      end

      test "returns false if the alert is closed" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        refute @delegated_closures_repo.display_review_buttons_for_closure_request?(@reviewer, create_closure_request.reload, @alert)
      end

      test "returns true" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        @alert.stubs(:is_closed).returns(false)
        # Add a dismissed response for good measure
        closure_request = create_closure_request
        response = Exemptions::ExemptionResponse.approve!(closure_request, @reviewer)
        response.status = Exemptions::ExemptionResponse::STATUSES[:dismissed]
        response.save!
        assert @delegated_closures_repo.display_review_buttons_for_closure_request?(@reviewer, closure_request.reload, @alert)
      end
    end

    context "user_can_review_closure_requests?" do
      test "returns false if the feature isn't enabled" do
        @delegated_closures_repo.stubs(:enabled?).returns(false)
        refute @delegated_closures_repo.user_can_review_closure_requests?(@user)
      end

      test "returns false if the user doesn't have the FGP" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        refute @delegated_closures_repo.user_can_review_closure_requests?(@user)
      end

      test "returns true" do
        @delegated_closures_repo.stubs(:enabled?).returns(true)
        SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:user_can_review_closure_requests?).returns(true)
        assert @delegated_closures_repo.user_can_review_closure_requests?(@user)
      end
    end

    def create_closure_request
      Exemptions::ExemptionRequest.create(
        requester: @user,
        resource_owner: @repo.reload,
        resource_identifier: "3",
        repository: @repo.reload,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me"
      )
    end
  end
end
