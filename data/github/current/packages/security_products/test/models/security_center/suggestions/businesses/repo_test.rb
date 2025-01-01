# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class RepoTest < GitHub::TestCase
        fixtures do
          if GitHub.enterprise?
            @business_owner = create(:user, login: "test-biz-admin")
            @business = create(:business, owners: [@business_owner])
            @org_admin = create(:user, business: @business, login: "test-org-admin")
            @user_a = create(:user, business: @business, login: "test-user-a")
            @user_b = create(:user, business: @business, login: "test-user-b")
          else
            @business = create(:business, :enterprise_managed)
            @business_owner = create(:emu, :owner, business: @business, login: "test-biz-admin")
            @org_admin = create(:emu, business: @business, login: "test-org-admin")
            @user_a = create(:emu, business: @business, login: "test-user-a")
            @user_b = create(:emu, business: @business, login: "test-user-b")
          end

          @org_1 = create(:organization, business: @business, login: "org-apple-1", admin: @org_admin)
          @org_1_repo_1 = create(:repository, owner: @org_1, name: "org-apple-repo-1")
          @org_1_repo_2 = create(:repository, owner: @org_1, name: "org-apple-repo-2")
          @org_1_repo_3 = create(:repository, owner: @org_1, name: "org-apple-repo-3")

          @org_2 = create(:organization, business: @business, login: "org-banana-2", admin: @org_admin)
          @org_2_repo_1 = create(:repository, owner: @org_2, name: "org-banana-repo-1")
          @org_2_repo_2 = create(:repository, owner: @org_2, name: "org-banana-repo-2")
          @org_2_repo_3 = create(:repository, owner: @org_2, name: "org-banana-repo-3")

          [@org_1_repo_1, @org_1_repo_2, @org_1_repo_3, @org_2_repo_1, @org_2_repo_2, @org_2_repo_3].each do |repo|
            create(:repository_security_center_config, repository: repo)
          end

          @user_repo_a1 = create(:private_repository, owner: @user_a, name: "user-repo-a1")
          @user_repo_a2 = create(:private_repository, owner: @user_a, name: "user-repo-a2")
          @user_repo_a3 = create(:private_repository, owner: @user_a, name: "user-repo-a3")

          @user_repo_b1 = create(:private_repository, owner: @user_b, name: "user-repo-b1")
          @user_repo_b2 = create(:private_repository, owner: @user_b, name: "user-repo-b2")
          @user_repo_b3 = create(:private_repository, owner: @user_b, name: "user-repo-b3")

          [
            @user_repo_a1, @user_repo_a2, @user_repo_a3,
            @user_repo_b1, @user_repo_b2, @user_repo_b3
          ].each do |repo|
            create(:repository_security_center_config, repository: repo)
          end
        end

        setup do
          @business.mark_advanced_security_as_purchased_for_entity(actor: @business_owner)
        end

        context "when requested from business owner" do
          test "it returns suggestions for all authorized orgs and EMU users" do
            suggestions = Repo.new(authorized_orgs: [@org_1], business: @business, user: @business_owner).suggestions

            assert_suggestions([
              @org_1_repo_1, @org_1_repo_2, @org_1_repo_3,
              @user_repo_a1, @user_repo_a2, @user_repo_a3,
              @user_repo_b1, @user_repo_b2, @user_repo_b3
            ], suggestions)
          end

          test "it returns EMU repos when authorized_orgs is empty" do
            suggestions = Repo.new(authorized_orgs: [], business: @business, user: @business_owner).suggestions

            assert_suggestions([
              @user_repo_a1, @user_repo_a2, @user_repo_a3,
              @user_repo_b1, @user_repo_b2, @user_repo_b3
            ], suggestions)
          end

          test "it returns no EMU repos if EMU is not supported" do
            if GitHub.enterprise?
              GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
            else
              @business.mark_advanced_security_as_not_purchased_for_entity(actor: @business_owner)
            end
            suggestions = Owner.new(authorized_orgs: [], business: @business, user: @business_owner).suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns suggestions from EMU accounts given a matching owner in NWO form" do
            suggestions = Repo.new(authorized_orgs: [@org_1], business: @business, user: @business_owner, value: "#{@user_a}/").suggestions

            assert_suggestions([@user_repo_a1, @user_repo_a2, @user_repo_a3], suggestions)
          end

          test "it returns no suggestion if the owner does not match" do
            suggestions = Repo.new(authorized_orgs: [@org_1], business: @business, user: @business_owner, value: "unknown/").suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns suggestions on submatches against an org name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @business_owner, value: "org-banana-2").suggestions

            assert_suggestions([@org_2_repo_1, @org_2_repo_2, @org_2_repo_3], suggestions)
          end

          test "it returns suggestions on submatches against a repo name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @business_owner, value: "banana-repo").suggestions

            assert_suggestions([@org_2_repo_1, @org_2_repo_2, @org_2_repo_3], suggestions)
          end

          test "it returns suggestions on submatches against an EMU name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @business_owner, value: "user-a").suggestions

            assert_suggestions([@user_repo_a1, @user_repo_a2, @user_repo_a3], suggestions)
          end

          test "it returns suggestions on submatches against an EMU repo name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @business_owner, value: "user-repo-b").suggestions

            assert_suggestions([@user_repo_b1, @user_repo_b2, @user_repo_b3], suggestions)
          end
        end

        context "when requested from a member" do
          test "it returns suggestions for all authorized orgs only" do
            suggestions = Repo.new(authorized_orgs: [@org_1], business: @business, user: @org_admin).suggestions

            assert_suggestions([
              @org_1_repo_1, @org_1_repo_2, @org_1_repo_3
            ], suggestions)
          end

          test "it returns no suggestion when authorized_orgs is empty" do
            suggestions = Repo.new(authorized_orgs: [], business: @business, user: @org_admin).suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns no suggestion for EMU owner matches" do
            suggestions = Repo.new(authorized_orgs: [@org_1], business: @business, user: @org_admin, value: "#{@user_a}/").suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns no suggestion if the owner does not match" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @org_admin, value: "unknown/").suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns suggestions on submatches against an org name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @org_admin, value: "org-banana-2").suggestions

            assert_suggestions([@org_2_repo_1, @org_2_repo_2, @org_2_repo_3], suggestions)
          end

          test "it returns suggestions on submatches against a repo name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @org_admin, value: "banana-repo").suggestions

            assert_suggestions([@org_2_repo_1, @org_2_repo_2, @org_2_repo_3], suggestions)
          end

          test "it returns no suggestion on submatches against an EMU name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @org_admin, value: "user-a").suggestions

            assert_suggestions([], suggestions)
          end

          test "it returns no suggestion on submatches against an EMU repo name" do
            suggestions = Repo.new(authorized_orgs: [@org_1, @org_2], business: @business, user: @org_admin, value: "user-repo-a").suggestions

            assert_suggestions([], suggestions)
          end
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Repo.new(
              authorized_orgs: [@org_1],
              business: @business,
              user: @business_owner,
              selected_values: [
                @org_1_repo_1.name_with_display_owner,
                @user_repo_a2.name_with_display_owner
              ]
            ).suggestions

            assert_suggestions([
              @org_1_repo_2, @org_1_repo_3,
              @user_repo_a1, @user_repo_a3,
              @user_repo_b1, @user_repo_b2, @user_repo_b3
            ], suggestions)
          end

          context 'when a value of the form "org/repo" is provided' do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = Repo.new(
                authorized_orgs: [@org_1, @org_2],
                business: @business,
                user: @business_owner,
                selected_values: [@org_1_repo_1.name_with_display_owner],
                value: "#{@org_1.display_login}/apple-repo"
              ).suggestions

              assert_suggestions([@org_1_repo_2, @org_1_repo_3], suggestions)
            end
          end

          context 'when a value without a "/" is provided' do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = Repo.new(
                authorized_orgs: [@org_1, @org_2],
                business: @business,
                user: @business_owner,
                selected_values: [@org_1_repo_1.name_with_display_owner],
                value: "-1"
              ).suggestions

              assert_suggestions([@org_1_repo_2, @org_1_repo_3, @org_2_repo_1], suggestions)
            end
          end
        end

        context 'when a value of the form "org/repo" is provided' do
          test "it returns suggestions for that org only" do
            suggestions = Repo.new(
              authorized_orgs: [@org_1, @org_2],
              business: @business,
              user: @business_owner,
              value: "#{@org_1.display_login}/apple-repo"
            ).suggestions

            assert_suggestions([
              @org_1_repo_1, @org_1_repo_2, @org_1_repo_3,
            ], suggestions)
          end
        end

        test "it returns suggestions in ascending alphabetical order by repo name, owner name" do
          suggestions = Repo.new(
            authorized_orgs: [@org_1, @org_2],
            business: @business,
            user: @business_owner,
          ).suggestions

          expected_suggestions = [
            @org_1_repo_1, @org_1_repo_2, @org_1_repo_3,
            @org_2_repo_1, @org_2_repo_2, @org_2_repo_3,
            @user_repo_a1, @user_repo_a2, @user_repo_a3,
            @user_repo_b1, @user_repo_b2, @user_repo_b3,
          ].map do |repo|
            Suggestion.new(
              description: repo.owner_display_login,
              label: repo.name,
              value: repo.name_with_display_owner
            )
          end

          assert_equal expected_suggestions, suggestions
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Repo.new(
              authorized_orgs: [@org_1, @org_2],
              business: @business,
              user: @business_owner,
              limit: 2
            ).suggestions

            assert_suggestions([@org_1_repo_1, @org_1_repo_2], suggestions)
          end
        end

        private

        def assert_suggestions(expected_repos, actual_suggestions)
          expected_suggestions = expected_repos.map do |repo|
            Suggestion.new(
              description: repo.owner_display_login,
              label: repo.name,
              value: repo.name_with_display_owner
            )
          end

          assert_same_elements(expected_suggestions, actual_suggestions)
        end
      end
    end
  end
end
