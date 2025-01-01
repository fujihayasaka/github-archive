# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SignupTest < GitHub::BillingTestCase

  fixtures do
    @user = create(:user, plan: nil)
    @org = create(:organization)
  end

  context "validations" do
    test "ensure the presence of a plan" do
      signup = Billing::Signup.new(user: @user, plan_name: "invalid plan", actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:plan, :blank)
    end

    test "fail if the user is not persisted" do
      signup = Billing::Signup.new(user: User.new, plan_name: "pro", actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:user, :invalid)
    end

    test "fail if the user is invalid" do
      @user.login = "_123"
      assert @user.invalid?

      signup = Billing::Signup.new(user: @user, plan_name: "pro", actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:user, :invalid)
    end

    test "fails if the user has already signed up" do
      signed_up_user = create(:user, :zuora)

      signup = Billing::Signup.new(user: signed_up_user, plan_name: "pro", actor: signed_up_user)

      refute signup.valid?
      assert signup.errors.of_kind?(:user, :already_signed_up)
    end

    test "fails if the plan is free since signup requires a paid plan" do
      signup = Billing::Signup.new(user: @user, plan_name: "free", actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:plan, :not_paid)
    end

    test "fails if a user attempts to sign up with an organization plan" do
      plan = GitHub::Plan.non_free_org_plans.first.name
      signup = Billing::Signup.new(user: @user, plan_name: plan, actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:plan, :invalid_plan_type_for_user)
    end

    test "fails if an organization attempts to sign up with a user plan" do
      plan = GitHub::Plan.non_free_user_plans[0].name
      signup = Billing::Signup.new(user: @org, plan_name: plan, actor: @user)

      refute signup.valid?
      assert signup.errors.of_kind?(:plan, :invalid_plan_type_for_user)
    end

    test "fails when attempting to move back an org to per repository plan" do
      org = create :organization, plan: "business", seats: 5
      signup = Billing::Signup.new(user: org, plan_name: "bronze", actor: org.admin)

      refute signup.valid?
      assert signup.errors.of_kind?(:plan, :invalid_plan_for_user)
    end
  end
end
