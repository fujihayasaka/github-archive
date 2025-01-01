# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomerAccountTest < GitHub::TestCase
  test "requires a customer" do
    customer_account = CustomerAccount.new
    customer_account.user = create(:user)

    refute customer_account.save
    assert customer_account.errors[:customer]
  end

  test "requires a user" do
    customer_account = CustomerAccount.new
    customer_account.customer = create :customer

    refute customer_account.save
    assert customer_account.errors[:user]
  end

  test "requires a unique user per purpose" do
    customer_account1 = create(:customer_account)
    customer_account2 = CustomerAccount.new(purpose: customer_account1.purpose, user: customer_account1.user)
    refute_predicate customer_account2, :valid?
    assert_includes customer_account2.errors[:user_id], "has already been taken"
  end

  test "allows a user to have a customer account of each purpose" do
    customer_account1 = create(:customer_account, purpose: :general)
    customer2 = create(:customer, :sponsors_invoiced)
    customer_account2 = build(:customer_account, purpose: :sponsors, user: customer_account1.user,
      customer: customer2)
    assert_predicate customer_account2, :valid?
  end

  test "disallows sponsors customer account for general customer" do
    customer = create(:customer)
    customer_account = CustomerAccount.new(purpose: :sponsors, customer: customer)
    refute_predicate customer_account, :valid?
    assert_includes customer_account.errors[:purpose], "must be general to match customer"
  end

  test "disallows general customer account for sponsors customer" do
    customer = create(:customer, :sponsors_invoiced)
    customer_account = CustomerAccount.new(purpose: :general, customer: customer)
    refute_predicate customer_account, :valid?
    assert_includes customer_account.errors[:purpose], "must be sponsors to match customer"
  end

  test "create" do
    customer_account = CustomerAccount.new
    customer_account.user = create(:user)
    customer_account.customer = create :customer

    assert customer_account.save
    refute customer_account.verified?
    assert_nil customer_account.organization
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "create with organization" do
    customer_account = CustomerAccount.new
    customer_account.user = create(:organization)
    customer_account.customer = create :customer

    assert customer_account.save
    refute customer_account.verified?
    assert customer_account.organization
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "verify user account" do
    customer_account = create :customer_account
    verified_by = customer_account.user

    assert customer_account.verify(customer_account.verification_token, verified_by)
    assert customer_account.verified?
    assert customer_account.verification_confirmed_at
    assert_nil customer_account.verification_token
    assert_equal verified_by, customer_account.verified_by
  end

  test "verify user account requires correct token" do
    customer_account = create :customer_account
    verified_by = customer_account.user

    refute customer_account.verify("abcd", verified_by)
    refute customer_account.verified?
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "verify user account fails unless acting on self" do
    customer_account = create :customer_account
    verified_by = create(:user)

    refute customer_account.verify(customer_account.verification_token, verified_by)
    refute customer_account.verified?
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "verify org account" do
    verified_by = create(:user)
    org = create :organization, admin: verified_by
    customer_account = create :customer_account, user: org

    assert customer_account.verify(customer_account.verification_token, verified_by)
    assert customer_account.verified?
    assert customer_account.verification_confirmed_at
    assert_nil customer_account.verification_token
    assert_equal verified_by, customer_account.verified_by
  end

  test "verify org account requires correct token" do
    verified_by = create(:user)
    org = create :organization, admin: verified_by
    customer_account = create :customer_account, user: org

    refute customer_account.verify("abcd", verified_by)
    refute customer_account.verified?
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "verify org account fails for non owner" do
    verified_by = create(:user)
    org = create :organization, admin: create(:user)
    customer_account = create :customer_account, user: org

    refute customer_account.verify(customer_account.verification_token, verified_by)
    refute customer_account.verified?
    assert_nil customer_account.verification_confirmed_at
    assert_nil customer_account.verified_by
    assert customer_account.verification_token
  end

  test "can only verify customer account once" do
    customer_account = create :customer_account
    verified_by = customer_account.user
    customer_account.verify(customer_account.verification_token, verified_by)

    first_verified_at = customer_account.verification_confirmed_at

    Timecop.freeze(1.day.from_now) do
      refute customer_account.verify(nil, verified_by),
        "shouldn't be able to verify a second time"
      assert_equal first_verified_at.to_i,
        customer_account.verification_confirmed_at.to_i
    end
  end

  test "destroys customer if its last customer account is deleted" do
    customer_account = create :customer_account
    customer         = customer_account.customer
    customer_account.destroy

    assert customer.destroyed?
  end

  test "does not destroy customer after customer account deletion if it was not the last account" do
    customer = create :customer

    user = create :user
    customer_account_1 = create(:customer_account, user: user, customer: customer)
    user = create :user
    customer_account_2 = create(:customer_account, user: user, customer: customer)

    customer_account_1.destroy

    refute customer.destroyed?
  end

  test "doesn't destroy customer if its still attached to a Business" do
    customer = create :customer
    business = create :business
    customer.business = business

    customer_account_1 = CustomerAccount.new
    customer_account_1.user = create(:user)
    customer_account_1.customer = customer

    customer_account_1.destroy

    refute customer.destroyed?
  end
end
