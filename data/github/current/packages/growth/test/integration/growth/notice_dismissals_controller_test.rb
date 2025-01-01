# typed: true
# frozen_string_literal: true

require "test_helper"

module Growth
  class NoticeDismissalsControllerTest < GitHub::IntegrationTestCase

    fixtures do
      @user = create(:user)
    end

    setup do
      enable_feature_flag(:growth_kv)
      @handler = Growth::NoticeDismissal.new(@user)
    end

    test "should dismiss business notice" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", business_id: 1 }
      assert_response :created
      assert @handler.dismissed_business_notice?("test_notice_name", business_id: 1)
    end

    test "should dismiss organization notice" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", organization_id: 1 }
      assert_response :created
      assert @handler.dismissed_organization_notice?("test_notice_name", organization_id: 1)
    end

    test "dismisses organization notice with specified expiration time" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", organization_id: 1, expires: 1.day.from_now }
      assert_response :created
      assert @handler.dismissed_organization_notice?("test_notice_name", organization_id: 1)

      Timecop.travel(2.days.from_now) do
        refute @handler.dismissed_organization_notice?("test_notice_name", organization_id: 1)
      end
    end

    test "should dismiss user notice" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name" }
      assert_response :created
      assert @handler.dismissed_user_notice?("test_notice_name")
    end

    test "dismisses user notice with specified expiration time" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", expires: 1.day.from_now }
      assert_response :created
      assert @handler.dismissed_user_notice?("test_notice_name")

      Timecop.travel(2.days.from_now) do
        refute @handler.dismissed_user_notice?("test_notice_name")
      end
    end

    test "should dismiss repo notice" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", repository_id: 2 }
      assert_response :created
      assert @handler.dismissed_repository_notice?("test_notice_name", repository_id: 2)
    end

    test "dismisses repository notice with specified expiration time" do
      as @user
      post  "/growth/notice_dismissals", params: { notice: "test_notice_name", repository_id: 2, expires: 1.day.from_now }
      assert_response :created
      assert @handler.dismissed_repository_notice?("test_notice_name", repository_id: 2)

      Timecop.travel(2.days.from_now) do
        refute @handler.dismissed_repository_notice?("test_notice_name", repository_id: 2)
      end
    end

    test "should return bad request when notice parameter is blank" do
      as @user
      post "/growth/notice_dismissals", params: { notice: "" }, as: :json
      assert_response :bad_request
      assert_equal "Notice parameter is required", JSON.parse(response.body)["error"]
    end

    test "should return service unavailable when GitHub::KV::UnavailableError is raised" do
      Growth::KV.stub(:store, -> { raise GitHub::KV::UnavailableError }) do
        as @user
        post("/growth/notice_dismissals", params: { notice: "test_notice_name" }, format: :json)
        assert_response :service_unavailable
        assert_equal "Service is currently unavailable. Please try again later.", JSON.parse(response.body)["error"]
      end
    end

    test "should return bad request when more than one *_id parameter is provided" do
      as @user
      post "/growth/notice_dismissals", params: { notice: "test_notice_name", business_id: 1, organization_id: 1 }, format: :json
      assert_equal 'Please specify at most one entity type: "business_id", "organization_id" or "repository_id"', JSON.parse(response.body)["error"]
      assert_response :bad_request
    end

    test "dismisses business notice for current user if per_user is true" do
      another_user = create(:user)
      another_user_handler = Growth::NoticeDismissal.new(another_user)

      as @user
      post "/growth/notice_dismissals", params: { notice: "test_notice_name", business_id: 1, per_user: true }, format: :json
      assert_response :success
      assert @handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: true)
      refute @handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: false)

      refute another_user_handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: false)
      refute another_user_handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: true)
    end

    test "dismisses business notice for whole entity if per_user is false" do
      another_user = create(:user)
      another_user_handler = Growth::NoticeDismissal.new(another_user)

      as @user
      post "/growth/notice_dismissals", params: { notice: "test_notice_name", business_id: 1, per_user: false }, format: :json
      assert_response :success
      assert @handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: false)
      refute @handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: true)

      assert another_user_handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: false)
      refute another_user_handler.dismissed_business_notice?("test_notice_name", business_id: 1, per_user: true)
    end

    test "dismisses business notice with specified expiration time" do
      as @user
      post "/growth/notice_dismissals", params: { notice: "test_notice_name", business_id: 1, expires: 1.day.from_now }, format: :json
      assert_response :success
      assert @handler.dismissed_business_notice?("test_notice_name", business_id: 1)

      Timecop.travel(2.days.from_now) do
        refute @handler.dismissed_business_notice?("test_notice_name", business_id: 1)
      end
    end
  end
end
