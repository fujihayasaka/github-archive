# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::CodeButton
    class PayloadTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        repo = create(:repository, admin: @user, from_example: :pull_request_history)
        create(:collaborator, collaborator: @user, repository: repo)
        assert repo.member?(@user)

        @pull = create(:pull_request,
          base_ref: repo.default_branch,
          base_repository: repo,
          base_user: @user,
          head_ref_name: "topic",
          head_repository: repo,
          head_user: @user,
          repository: repo,
          user: @user,
        )

        # Codespace access differs depending on test mode (dotcom vs MT vs EMU), so rather than jump through
        # hoops to set up the user, repo, org, etc. data correctly for each mode, we're stubbing it out.
        has_access_to_codespaces = !GitHub.enterprise?
        Codespaces::MenuVisibility.any_instance.stubs(:has_access_to_codespaces?).returns(has_access_to_codespaces)

        @expected_payload = {
          "contactPath" => "/contact",
          "currentUserIsEnterpriseManaged" => false,
          "enterpriseManagedBusinessName" => "",
          "hasAccessToCodespaces" => has_access_to_codespaces,
          "isLoggedIn" => true,
          "newCodespacePath" => "/codespaces/new?hide_repo_select=true&ref=#{@pull.head_ref}&repo=#{@pull.repository_id}",
          "repositoryPolicyInfo" => {
            "allowed" => true,
            "canBill" => true,
            "changesWouldBeSafe" => true,
            "disabledByBusiness" => false,
            "disabledByOrganization" => false,
            "hasIpAllowLists" => false,
          },
        }
      end

      test "serializes the code button with Ruby conventions using to_hash" do
        data = PullRequests::PageData::CodeButton::Loader.load(current_user: @user, pull_request: @pull)

        assert_no_queries do
          actual_payload = PullRequests::PageData::CodeButton::Payload.call(data)
          assert_equal @expected_payload.as_json, actual_payload.as_json
        end
      end
    end
  end
end
