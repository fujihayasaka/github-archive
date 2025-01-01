# typed: true
# frozen_string_literal: true

require "test_helper"

module Authz
  class RequestTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @business = create(:business)
    end

    setup do
      @permission = Permissions::FineGrainedPermissionIm.find!(:enterprise_test_read_permission).action.to_sym

      disable_feature_flag(:authzd_use_latest_generic_org_policy_version)
      disable_feature_flag(:authzd_use_latest_generic_business_policy_version)
    end

    context "when subject is an organization" do
      test "builds request hash using stable business policy version" do
        request = Request.new(actor: @user, permission: @permission, subject: @org)

        assert_equal Request::STABLE_ORG_POLICY_VERSION, request.authzd_request_hash[:context]["version"]
      end

      test "builds request hash using latest business policy version when FF is enabled" do
        enable_feature_flag(:authzd_use_latest_generic_org_policy_version, @org)
        request = Request.new(actor: @user, permission: @permission, subject: @org)

        assert_equal Request::LATEST_ORG_POLICY_VERSION, request.authzd_request_hash[:context]["version"]
      end
    end

    context "when subject is a business" do
      test "builds request hash using stable business policy version" do
        request = Request.new(actor: @user, permission: @permission, subject: @business)

        assert_equal Request::STABLE_BUSINESS_POLICY_VERSION, request.authzd_request_hash[:context]["version"]
      end

      test "builds request hash using latest business policy version when FF is enabled" do
        enable_feature_flag(:authzd_use_latest_generic_business_policy_version, @business)
        request = Request.new(actor: @user, permission: @permission, subject: @business)

        assert_equal Request::LATEST_BUSINESS_POLICY_VERSION, request.authzd_request_hash[:context]["version"]
      end
    end
  end
end
