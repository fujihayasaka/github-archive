# typed: true
# frozen_string_literal: true

require "test_helper"

class User::RemovalDependencyTest < GitHub::TestCase
  fixtures do
    @staffer   = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @janedoe   = create(:user, :with_trade_screening_record, login: "janedoe", email: "janedoe@example.com")
  end

  context "#remove!" do
    context "before destroying" do
      test "flags record as destroying" do
        DestroyUserCallbacks.any_instance.stubs(:before_transaction).with(@janedoe).returns(nil)
        @janedoe.stubs(:destroy!).returns(@janedoe)

        refute @janedoe.being_destroyed?

        @janedoe.remove!

        assert @janedoe.being_destroyed?
      end

      test "removes repositories" do
        create(:repository, owner: @janedoe)
        @janedoe.stubs(:destroy!).returns(@janedoe)

        assert_equal @janedoe.repositories.count, 1

        @janedoe.remove!

        assert_equal @janedoe.repositories.reload.count, 0
        assert_nothing_raised do
          @janedoe.reload
        end
      end

      test "removes public_org_members" do
        @janedoe.stubs(:destroy!).returns(@janedoe)
        owner = create(:user)
        org = create(:organization, admin: owner)
        team = create(:team, organization: org)
        team.add_member(@janedoe)
        org.publicize_member(@janedoe)

        assert_equal 1, org.public_members.size

        @janedoe.remove!

        assert_equal org.public_members.reload.size, 0
        assert_nothing_raised do
          @janedoe.reload
        end
      end

      test "removes issue assignments" do
        @janedoe.stubs(:destroy!).returns(@janedoe)
        repo = create(:repository, owner: @janedoe)
        create(:issue, repository: repo, user: @janedoe, assignee: @janedoe)

        assert_equal repo.issues.assigned_to("janedoe").count, 1

        @janedoe.remove!

        assert_equal repo.issues.assigned_to("janedoe").count, 0
        assert_nothing_raised do
          @janedoe.reload
        end
      end
    end
  end

  context "#never_deletable?" do
    test "true for legal hold user" do
      @janedoe.place_legal_hold(actor: @staffer)
      assert_predicate @janedoe, :never_deletable?
    end

    test "true for system user" do
      @janedoe.stubs(system_account?: true)
      assert_predicate @janedoe, :never_deletable?
    end

    test "false for trade controls restricted user" do
      @janedoe.stubs(has_any_trade_restrictions?: true)
      refute_predicate @janedoe, :never_deletable?
    end

    test "true for trade screening restricted user" do
      @janedoe.trade_screening_record.stubs(:delete_restricted?).returns(true)
      assert_predicate @janedoe, :never_deletable?
    end

    test "true for user with with solitarely owned organizations" do
      user = create(:user)
      org = create(:organization, admin: user)
      assert_predicate user, :never_deletable?
    end

    test "true for user with owned businesses" do
      user = create(:user)
      business = create(:business, owners: [user])
      assert_predicate user, :never_deletable?
    end unless GitHub.enterprise?

    test "false for regular user" do
      refute_predicate @janedoe, :never_deletable?
    end
  end
end
