# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersAccessTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @user = @plan_subscription.user

    @org = create(:organization)
    @org.add_member(@user)

    @cfb_org = create(:copilot_for_business_enabled_organization)
    @cfb_org.add_member(@user)
    Copilot::Organization.new(@cfb_org).seat_management_allow_all!

    @emu_user = create(:emu)

    @public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)
    @other_public_repo = create(:public_repository, name: "public-repo-2", created_at: 2.months.ago, pushed_at: 2.years.ago, owner: @user)

    @educational_coupon = create(:coupon, code: "students-2022")
    @non_educational_coupon = create(:coupon, group: "internal")

    @capable_app = create_internal_app_with_capabilities(
      capabilities: { generate_copilot_cdn_token: true }
    )

    @incapable_app = create_internal_app_with_capabilities(
      capabilities: { generate_copilot_cdn_token: false }
    )
  end

  context "#has_free_access?" do
    test "false by default" do
      refute Copilot::User.new(@user).has_free_access?
      assert find_span_by(name: "copilot.has_free_access")
    end

    test "just having a free user isn't enough" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: false)
      copilot_user = Copilot::User.new(user)
      refute copilot_user.has_free_access?
    end

    test "free user with valid access is enough" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      copilot_user = Copilot::User.new(user)

      assert copilot_user.has_free_access?
    end
  end

  context "#administrative_blocked?" do
    test "false by default" do
      refute Copilot::User.new(@user).administrative_blocked?
    end

    test "handles when feature flags are not available" do
      ActiveRecord::Base.disable_queries_to_databases(ApplicationRecord.clusters) do
        refute Copilot::User.new(@user).administrative_blocked?
      end
    end
  end

  context "#trade_restricted?" do
    test "false by default" do
      refute Copilot::User.new(@user).trade_restricted?
    end

    test "true when user has trade restrictions" do
      user = create(:user, :fully_trade_restricted)
      assert Copilot::User.new(user).trade_restricted?
    end

    test "false when the user has a screening restriction but the flag is disabled" do
      GitHub.flipper[:live_sdn_screening].disable

      user = create(:user, :with_sdn_screening_restriction)
      user.trade_screening_record.hit_in_review!

      refute Copilot::User.new(user).trade_restricted?
    end

    test "false when the user has not been screened" do
      GitHub.flipper[:live_sdn_screening].enable

      user = create(:user, :with_sdn_screening_restriction)
      user.trade_screening_record.not_screened!

      refute Copilot::User.new(user).trade_restricted?
    end

    test "false when the user has an allowed screening status" do
      GitHub.flipper[:live_sdn_screening].enable

      user = create(:user, :with_sdn_screening_restriction)
      user.trade_screening_record.no_hit!

      refute Copilot::User.new(user).trade_restricted?
    end
  end

  context "#free_user_blocked?" do
    test "false by default" do
      refute Copilot::User.new(@user).free_user_blocked?
    end

    test "true when user has a free user" do
      free_user = create(:copilot_free_user)
      GitHub.flipper[:copilot_free_user_blocked].enable(free_user.user)
      assert Copilot::User.new(free_user.user).free_user_blocked?
    end
  end

  context "#free_user_block!" do
    test "blocks the user" do
      free_user = create(:copilot_free_user)
      Copilot::User.new(free_user.user).free_user_block!
      assert Copilot::User.new(free_user.user).free_user_blocked?
    end
  end

  context "#free_user_unblock!" do
    test "unblocks the user" do
      free_user = create(:copilot_free_user)
      GitHub.flipper[:copilot_free_user_blocked].enable(free_user.user)
      Copilot::User.new(free_user.user).free_user_unblock!
      refute Copilot::User.new(free_user.user).free_user_blocked?
    end
  end

  context "#administrative_block!" do
    test "blocks the user" do
      actor = create(:user)
      Copilot::User.new(@user).administrative_block!(actor, "reason")
      assert Copilot::User.new(@user).administrative_blocked?
    end

    test "does not block hammy users" do
      actor = create(:user)
      @user.mark_as_hammy

      Copilot::User.new(@user).administrative_block!(actor, "reason")
      refute Copilot::User.new(@user).administrative_blocked?
    end
  end

  context "#administrative_unblock!" do
    test "unblocks the user if they were blocked by the legacy flag" do
      Copilot::User.new(@user).administrative_block!(create(:user), "reason")
      Copilot::User.new(@user).administrative_unblock!(create(:user))
      refute Copilot::User.new(@user).administrative_blocked?
    end

    test "unblocks the user" do
      actor = create(:user)
      Copilot::User.new(@user).administrative_block!(actor, "reason")
      Copilot::User.new(@user).administrative_unblock!(create(:user))
      refute Copilot::User.new(@user).administrative_blocked?
    end
  end

  context "#block_if_sharing_payment_method_with_other_blocked_users!" do
    test "blocks the user and returns true if they are sharing payment methods with two or more blocked users" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      user = create(:credit_card_user)
      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: user.customer.payment_method.card_fingerprint)
      other_blocked_user = create(:credit_card_user)
      other_blocked_user.customer.payment_method.update(card_fingerprint: user.customer.payment_method.card_fingerprint)

      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")
      Copilot::User.new(other_blocked_user).administrative_block!(create(:user), "reason")

      assert Copilot::User.new(user).block_if_sharing_payment_method_with_other_blocked_users!

      assert Copilot::User.new(user).administrative_blocked?
    end

    test "blocks the user and returns true if they are sharing payment methods with one blocked user and they are not trusted" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      user = create(:credit_card_user)
      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: user.customer.payment_method.card_fingerprint)
      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")

      user.settings.set!(:trust_tier, "2")
      assert TrustTiers::Tier.for_billable_owner(user).tier == TrustTiers::Tier::NEUTRAL

      assert Copilot::User.new(user).block_if_sharing_payment_method_with_other_blocked_users!

      assert Copilot::User.new(user).administrative_blocked?
    end

    test "doesn't block the user if they're sharing a payment method with one or more blocked users and they're trusted" do
      GitHub.flipper[:copilot_block_shared_payment_methods].enable

      user = create(:credit_card_user)

      refute Copilot::User.new(user).block_if_sharing_payment_method_with_other_blocked_users!
      refute Copilot::User.new(user).administrative_blocked?

      blocked_user = create(:credit_card_user)
      blocked_user.customer.payment_method.update(card_fingerprint: user.customer.payment_method.card_fingerprint)

      Copilot::User.new(blocked_user).administrative_block!(create(:user), "reason")
      user.settings.set!(:trust_tier, "1")
      assert TrustTiers::Tier.for_billable_owner(user).tier == TrustTiers::Tier::TRUSTED

      refute Copilot::User.new(user).block_if_sharing_payment_method_with_other_blocked_users!
      refute Copilot::User.new(user).administrative_blocked?
    end
  end

  context "#has_cfb_access" do
    test "is always true if the user has a seat" do
      assignment = create(:copilot_seat_assignment, :organization)
      assignment.convert_to_seats

      assert Copilot::User.new(assignment.seats.first.assigned_user).has_cfb_access?
    end

    test "returns true when the user is a member of an enterprise team" do
      # We specifically don't want to convert to seats here. That is because
      # of multiple bugs in the code that would normally create seats for users in a team.
      # See https://github.com/github/heart-services/issues/4142
      # So, we need to ensure that this method will also return true when a user has ONLY a seat assignment
      # for the enterprise team to which they belong.
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = assignment.assignable

      assert Copilot::User.new(User.find(enterprise_team.member_user_ids.first)).has_cfb_access?
    end
  end
end if GitHub.copilot_enabled?
