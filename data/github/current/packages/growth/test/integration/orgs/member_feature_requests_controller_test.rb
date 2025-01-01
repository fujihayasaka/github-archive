# typed: true
# frozen_string_literal: true

require "test_helper"

class Orgs::MemberFeatureRequestsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin, login: "myorg")
    @member = create(:user)

    @business_owner = create(:user)
    @enterprise_org_admin = create(:user)
    @business = create(:business, owners: [@business_owner])
    @enterprise_organization = create(:enterprise_linked_organization, business: @business, admin: @enterprise_org_admin, login: "enterpriseorg")
  end

  setup do
    @org.add_member(@member)
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s for emu or enterprise server" do
      test "POST /orgs/myorg/member_feature_request" do
        as @member
        post "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        assert_response_not_found
      end

      test "DELETE /orgs/myorg/member_feature_request" do
        feature_request = create(:member_feature_request, request_entity: @org, requester: @member, feature: MemberFeatureRequest::Feature::ProtectedBranches)
        as @member
        delete "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        assert_response_not_found
      end
    end
  else
    context "POST #create" do
      test "redirects to login for anon" do
        @session.clear
        as nil

        url = "/orgs/myorg/member_feature_request"
        post url, params: { feature: "protected_branches" }

        assert_redirected_to login_path(return_to: "http://github.com#{url}")
      end

      test "renders 404 when you don't have access to the org" do
        another_org = create(:organization, login: "anotherorg")
        as @member

        post "/orgs/anotherorg/member_feature_request", params: { feature: "protected_branches" }

        assert_response :not_found
      end

      test "renders 403 when you are a business owner" do
        as @business_owner

        post "/orgs/enterpriseorg/member_feature_request", params: { feature: "copilot_for_business" }

        assert_response :forbidden
      end

      test "creates a request when valid" do
        as @member

        assert_difference -> { MemberFeatureRequest.count } do
          post "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        end

        assert_response :ok
      end

      test "creates a request when you are an outside collaborator" do
        outside_collaborator = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(outside_collaborator)
        as outside_collaborator

        assert_difference -> { MemberFeatureRequest.count } do
          post "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        end

        assert_response :ok
      end

      test "creates a request with billing_entity for org admin" do
        as @enterprise_org_admin

        assert_difference -> { MemberFeatureRequest.count } do
          post "/orgs/enterpriseorg/member_feature_request", params: { feature: "copilot_for_business" }
        end

        assert_response :ok
      end

      test "renders an error when feature is invalid" do
        as @member

        assert_no_difference -> { MemberFeatureRequest.count } do
          post "/orgs/myorg/member_feature_request", params: { feature: "non_existent_feature" }
        end

        assert_response :unprocessable_entity
        assert_match /Feature can't be blank or is invalid/, response.body
      end

      test "renders an error when request feature was already requested" do
        create(:member_feature_request, request_entity: @org, requester: @member, feature: MemberFeatureRequest::Feature::ProtectedBranches)

        as @member

        assert_no_difference -> { MemberFeatureRequest.count } do
          post "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        end

        assert_response :unprocessable_entity
        assert_match /Feature already requested/, response.body
      end

      test "updates a request when feature was already requested and fulfilled" do
        feature_request = create(:member_feature_request, request_entity: @org, requester: @member, feature: MemberFeatureRequest::Feature::CopilotForBusiness, status: :fulfilled)
        as @member

        assert_no_difference -> { MemberFeatureRequest.count } do
          assert_changes(-> { feature_request.reload.status }, from: "fulfilled", to: "requested") do
            post "/orgs/myorg/member_feature_request", params: { feature: "copilot_for_business" }
          end
        end

        assert_response :ok
      end
    end

    context "DELETE #destroy" do
      test "redirects to login for anon" do
        @session.clear
        as nil

        url = "/orgs/myorg/member_feature_request"
        delete url, params: { feature: "protected_branches" }

        assert_redirected_to login_path(return_to: "http://github.com#{url}")
      end

      test "renders 404 when you don't have access to the org" do
        another_org = create(:organization, login: "anotherorg")
        another_user = create(:user)
        another_org.add_member(another_user)
        feature_request = create(:member_feature_request, request_entity: another_org, requester: another_user, feature: MemberFeatureRequest::Feature::ProtectedBranches)
        as @member

        delete "/orgs/anotherorg/member_feature_request", params: { feature: "protected_branches" }

        assert_response :not_found
      end

      test "renders 403 when you are a business owner" do
        feature_request = create(:member_feature_request, request_entity: @org, requester: @member, feature: MemberFeatureRequest::Feature::ProtectedBranches)
        as @business_owner

        delete "/orgs/enterpriseorg/member_feature_request", params: { feature: "copilot_for_business" }

        assert_response :forbidden
      end

      test "cancels a request with success" do
        feature_request = create(:member_feature_request, request_entity: @org, requester: @member, feature: MemberFeatureRequest::Feature::ProtectedBranches)
        as @member

        assert_difference -> { MemberFeatureRequest.count }, -1 do
          delete "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }
        end

        assert_response :no_content
      end

      test "error when canceling a request that user does not owns" do
        another_user = create(:user)
        @org.add_member(another_user)
        feature_request = create(:member_feature_request, request_entity: @org, requester: another_user, feature: MemberFeatureRequest::Feature::ProtectedBranches)
        as @member

        delete "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }

        assert_response :not_found
      end

      test "error when canceling a request that does not exists" do
        as @member

        delete "/orgs/myorg/member_feature_request", params: { feature: "protected_branches" }

        assert_response :not_found
      end
    end
  end
end
