# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module PageNavigators
    class OrgPageNavigatorTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @org = create(:organization, plan_subscription: create(:billing_plan_subscription))
        @repo = create(:repository, owner: @org)
      end

      setup do
        @user = build(:user)
        org_scoped_context = build_context(current_user: @user, scope: @org)
        @org_scoped_navigator = OrgPageNavigator.new(org_scoped_context)
      end

      context "unscoped context" do
        test "returns empty array" do
          unscoped_context = build_context(current_user: @user, scope: nil)
          navigator = OrgPageNavigator.new(unscoped_context)
          assert_predicate navigator.items, :empty?
        end
      end

      context "scoped context" do
        test "returns valid items" do
          @org_scoped_navigator.items.each do |item|
            assert_result_structure(item)
            assert_equal item.object, @org
          end
        end

        test "includes the link to organization" do
          items = @org_scoped_navigator.items
          first_item = items.first

          assert_equal @org.login, first_item.title
          assert_equal "pages", first_item.group
          assert_equal "Jump to", first_item.hint
          assert_result_structure(first_item)
        end

        test "includes the Discussions page" do
          create(:organization_discussion_config, organization: @org, repository: @repo)

          items = @org_scoped_navigator.items
          assert_includes items.map(&:title), "Discussions"
          assert_result_structure(items.find { |item| item.title == "Discussions" })
        end

        if GitHub.sponsors_enabled?
          test "does not include the Sponsoring page" do
            refute_includes @org_scoped_navigator.items.map(&:title), "Sponsoring"
          end
        end

        test "does not include the Settings page" do
          refute_includes @org_scoped_navigator.items.map(&:title), "Settings"
        end

        if GitHub.sponsors_enabled?
          context "when an org is the sponsor in a sponsorship visible to the viewer" do
            test "includes the Sponsoring page" do
              create(:sponsorship, sponsor: @org)
              create(:user_metadata, user: @org, sponsoring_count: 1)

              items = @org_scoped_navigator.items
              assert_includes items.map(&:title), "Sponsoring"
              assert_result_structure(items.find { |item| item.title == "Sponsoring" })
            end
          end

          context "when an org is the sponsor in a sponsorship not visible to the viewer" do
            test "does not include the Sponsoring page" do
              create(:sponsorship, :private, sponsor: @org)
              create(:user_metadata, user: @org, sponsoring_public_and_private_count: 1, sponsoring_count: 0)

              refute_includes @org_scoped_navigator.items.map(&:title), "Sponsoring"
            end
          end
        end

        context "when user is an org admin" do
          test "includes the Settings page" do
            @org.stubs(:adminable_by?).with(@user).returns(true)

            items = @org_scoped_navigator.items
            assert_includes items.map(&:title), "Settings"
            assert_result_structure(items.find { |item| item.title == "Settings" })
          end
        end

        context "when user is an biling manager" do
          test "includes the Settings page" do
            @org.stubs(:billing_manager?).with(@user).returns(true)

            items = @org_scoped_navigator.items
            assert_includes items.map(&:title), "Settings"
            assert_result_structure(items.find { |item| item.title == "Settings" })
          end
        end

        context "when user is an integration manager" do
          test "includes the Settings page" do

            @org_scoped_navigator.stubs(:manages_any_integration?).with(user: @user, organization: @org).returns(true)

            items = @org_scoped_navigator.items
            assert_includes items.map(&:title), "Settings"
            assert_result_structure(items.find { |item| item.title == "Settings" })
          end
        end
      end
    end
  end
end
