# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class OrganizationResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
      end

      context "adds priority weights" do
        test "when there is no affiliation it defaults" do
          org_non_affiliated = build(:organization)
          assert_equal Result.jump_to(org_non_affiliated, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:org_default]
        end

        test "when admin" do
          org_admin = create(:organization, admins: [@user])
          org_admin.add_member(@user)
          assert_equal Result.jump_to(org_admin, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:admin]
        end

        test "when member" do
          org_member = create(:organization)
          org_member.add_member(@user)
          assert_equal Result.jump_to(org_member, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:member]
        end

        test "when billing_manager" do
          org_billing = create(:organization)
          org_billing.billing.add_manager(@user, actor: org_billing.admin)
          assert_equal Result.jump_to(org_billing, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:billing_manager]
        end

        test "when outside_collaborator" do
          org_collaborator = create(:organization)
          create(:repository, owner: org_collaborator).add_member(@user)
          assert_equal Result.jump_to(org_collaborator, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:outside_collaborator]
        end

        test "when there are multiple roles" do
          org_member_and_billing = create(:organization)
          org_member_and_billing.add_member(@user)
          org_member_and_billing.billing.add_manager(@user, actor: org_member_and_billing.admin)

          org_admin_and_billing = create(:organization, admins: [@user])
          org_admin_and_billing.add_member(@user)
          org_admin_and_billing.billing.add_manager(@user, actor: org_admin_and_billing.admin)

          org_collaborator_and_billing = create(:organization)
          create(:repository, owner: org_collaborator_and_billing).add_member(@user)
          org_collaborator_and_billing.billing.add_manager(@user, actor: org_collaborator_and_billing.admin)

          assert_equal Result.jump_to(org_member_and_billing, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:member]
          assert_equal Result.jump_to(org_admin_and_billing, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:admin]

          assert_equal Result::PRIORITY_WEIGHTS[:outside_collaborator], Result::PRIORITY_WEIGHTS[:billing_manager]
          assert_equal Result.jump_to(org_collaborator_and_billing, context: context).priority, 1 + Result::PRIORITY_WEIGHTS[:outside_collaborator]
        end
      end

      test "#max_role_based_weight defaults" do
        assert_equal OrganizationResult.max_role_based_weight([:unknown]), Result::PRIORITY_WEIGHTS[:org_default]
      end

      test "has a default group" do
        org_admin = build(:organization, admins: [@user])
        context = build_context(current_user: @user, scope: nil)
        result = Result.jump_to(org_admin, context: context)
        assert_equal :organizations, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          org_admin = build(:organization, admins: [@user])
          context = build_context(current_user: @user, scope: nil)
          result = Result.jump_to(org_admin, context: context, group: :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end

      def context
        # need a fresh context when changing the users org affiliations between tests
        build_context(current_user: @user)
      end
    end
  end
end
