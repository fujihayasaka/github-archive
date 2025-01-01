# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::DelistActionDataTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @action = create(:repository_action, repository: @repo)
    @current_user = create(:user)
  end

  context "#call" do
    context "repoAdminableByViewer" do
      context "when the action has a repository" do
        context "when the current user is an admin of the repository" do
          test "repoAdminableByViewer is true" do
            @repo.add_member(@current_user, action: :admin)
            result = Marketplace::Serializers::DelistActionData.new(@action, @current_user, "").call

            assert_equal true, result[:repoAdminableByViewer]
          end
        end

        context "when the current user is not an admin of the repository" do
          test "repoAdminableByViewer is false" do
            result = Marketplace::Serializers::DelistActionData.new(@action, @current_user, "").call

            assert_equal false, result[:repoAdminableByViewer]
          end
        end

        context "when current user is not present" do
          test "repoAdminableByViewer is false" do
            result = Marketplace::Serializers::DelistActionData.new(@action, nil, "").call

            assert_equal false, result[:repoAdminableByViewer]
          end
        end
      end

      context "when the action does not have a repository" do
        test "repoAdminableByViewer is false" do
          @action.stubs(:repository).returns(nil)
          result = Marketplace::Serializers::DelistActionData.new(@action, @current_user, "").call

          assert_equal false, result[:repoAdminableByViewer]
        end
      end
    end

    context "hydroAttrs" do
      test "returns the hydro click tracking attributes for the hydroAttrs" do
        request_url = "www.request.com"
        result = Marketplace::Serializers::DelistActionData.new(@action, @current_user, request_url).call

        assert result[:hydroAttrs].key?("hydro-click")
        assert result[:hydroAttrs].key?("hydro-click-hmac")
      end
    end
  end
end
