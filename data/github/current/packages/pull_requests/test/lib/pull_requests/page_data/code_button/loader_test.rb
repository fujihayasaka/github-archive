# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::CodeButton
    class LoaderTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :review_comment_fork)
        create(:collaborator, collaborator: @user, repository: @repository)
        assert @repository.member?(@user)

        @pull = create(:pull_request,
          :with_mergeable_head,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic2",
          user: @user,
        )

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "returns expected data for logged in user" do
        # Codespace access differs depending on test mode (dotcom vs MT vs EMU), so rather than jump through
        # hoops to set up the user, repo, org, etc. data correctly for each mode, we're stubbing it out.
        has_access_to_codespaces = !GitHub.enterprise?
        Codespaces::MenuVisibility.any_instance.stubs(:has_access_to_codespaces?).returns(has_access_to_codespaces)

        expected_data = {
          "contact_path" => "/contact",
          "current_user_is_enterprise_managed" => false,
          "enterprise_managed_business_name" => "",
          "has_access_to_codespaces" => has_access_to_codespaces,
          "is_logged_in" => true,
          "new_codespace_path" => "/codespaces/new?hide_repo_select=true&ref=#{@pull.head_ref}&repo=#{@repository.id}",
          "repository_policy_info" => {
            "allowed" => true,
            "can_bill" => true,
            "changes_would_be_safe" => true,
            "disabled_by_business" => false,
            "disabled_by_organization" => false,
            "has_ip_allowlists" => false,
          },
        }

        actual_data = PullRequests::PageData::CodeButton::Loader.load(pull_request: @pull, current_user: @user)
        assert_equal expected_data, actual_data.serialize
      end

      test "returns expected data for logged out user" do
        expected_data = {
          "contact_path" => "/contact",
          "current_user_is_enterprise_managed" => false,
          "enterprise_managed_business_name" => "",
          "has_access_to_codespaces" => false,
          "is_logged_in" => false,
          "new_codespace_path" => "/codespaces/new?hide_repo_select=true&ref=#{@pull.head_ref}&repo=#{@repository.id}",
          "repository_policy_info" => nil,
        }

        actual_data = PullRequests::PageData::CodeButton::Loader.load(pull_request: @pull, current_user: nil)

        # Due to problems with serializing Typed Structs, we are unable to do a straightforward equality assertion
        # on the expected vs actual data, and instead have to compare values manually.
        # See https://sorbet.org/docs/tstruct#serialize-gotchas
        assert_equal expected_data["contact_path"], actual_data.contact_path
        assert_equal expected_data["current_user_is_enterprise_managed"], actual_data.current_user_is_enterprise_managed
        assert_equal expected_data["enterprise_managed_business_name"], actual_data.enterprise_managed_business_name
        assert_equal expected_data["has_access_to_codespaces"], actual_data.has_access_to_codespaces
        assert_equal expected_data["is_logged_in"], actual_data.is_logged_in
        assert_equal expected_data["new_codespace_path"], actual_data.new_codespace_path
        assert_nil expected_data["repository_policy_info"]
        assert_nil actual_data.repository_policy_info
      end
    end
  end
end
