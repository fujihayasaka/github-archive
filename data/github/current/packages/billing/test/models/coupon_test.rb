# typed: true
# frozen_string_literal: true

require "test_helper"

class CouponTest < GitHub::TestCase
  include GitHub::BillingTest

  fixtures do
    @user   = create(:user, plan: "small")
    @user2  = create(:user, plan: "small")
    @coupon = create(:coupon, discount: 0.5)
  end

  setup do
    disable_feature_flag(:coupon_application_for_existing_ea)
  end

  context "#discount_in_cents" do
    test "returns the discount in cents" do
      coupon = build(:coupon, discount: 0.5)
      assert_equal 50, coupon.discount_in_cents

      coupon = build(:coupon, discount: 0.99)
      assert_equal 99, coupon.discount_in_cents

      coupon = build(:coupon, discount: 1.0)
      assert_equal 100, coupon.discount_in_cents
    end
  end

  context "#human_discount" do
    test "returns percentage discount as a human readable string if the discount is less than or equal to 1" do
      coupon = build(:coupon, discount: 0.5)
      assert_equal "50%", coupon.human_discount

      coupon = build(:coupon, discount: 0.99)
      assert_equal "99%", coupon.human_discount

      coupon = build(:coupon, discount: 1.0)
      assert_equal "100%", coupon.human_discount
    end

    test "returns the discount as a human readable string if the discount is greater than 1" do
      coupon = build(:coupon, discount: 5.0)
      assert_equal "$5.00", coupon.human_discount
    end
  end

  test "can generate an awesome, SHA-like code" do
    assert_equal 7, create(:coupon).code.size
    assert_equal @coupon.code, @coupon.reload.code
  end

  test "has some rules around code format" do
    assert_valid build(:coupon, code: "b")
    assert_valid build(:coupon, code: "abcd-123.456")
    assert_valid build(:coupon, code: "abcd_123+def")
    assert_valid build(:coupon, code: "GitHub<3hacksoton&2")

    refute build(:coupon, code: "no spaces").valid?
    refute build(:coupon, code: "no_%_percents").valid?
    refute build(:coupon, code: "no_#_hash_tags").valid?
    refute build(:coupon, code: "no_?_question_marks").valid?
    refute build(:coupon, code: "no_/_forward_slashes").valid?
    refute build(:coupon, code: "no_[]_brackets").valid?

    assert Coupon.valid_code? "abcd-123.456"
    refute Coupon.valid_code? "no_?_question_marks"
  end

  test "can be given percent for discount" do
    coupon = create(:coupon, discount: "50%")
    assert coupon.valid?
    assert_equal 0.5, coupon.discount
  end

  test "can be given dollars for discount" do
    coupon = create(:coupon, discount: "$12")
    assert coupon.valid?
    assert_equal 12.0, coupon.discount

    coupon = create(:coupon, discount: "12")
    assert coupon.valid?
    assert_equal 12.0, coupon.discount

    assert_equal create(:coupon, discount: "$12").discount,
      create(:coupon, discount: "$12.00").discount
  end

  test "can give free trials of specific plans" do
    coupon = create(:coupon, discount: "100%", plan: "micro")
    assert coupon.trial?
  end

  test "returns display plan name" do
    assert_equal "Micro", create(:coupon, discount: 1, plan: "micro").plan_display_name
  end

  test "default to a limit of 1" do
    assert_equal 1, @coupon.limit
  end

  test "default to a duration of 31 days" do
    assert_equal 31, @coupon.duration
  end

  test "requires the group field" do
    coupon = build(:coupon, group: nil)
    refute coupon.valid?
  end

  test "limits the group field to a list" do
    coupon = build(:coupon, group: "rawrbears")
    refute coupon.valid?
  end

  test "requires the note field" do
    coupon = build(:coupon, note: nil)
    refute coupon.valid?
  end

  test "will_expire? if the duration is less than 'forever'" do
    assert create(:coupon, duration: 365).will_expire?
    refute create(:coupon, duration: 29970).will_expire?
  end

  test "always returns expires_at in Pacfic timezone" do
    coupon = create :coupon
    coupon.expires_at = Time.current # UTC

    assert_equal GitHub::Billing.timezone, coupon.expires_at.time_zone
  end

  test ".clean_code!" do
    coupon = build(:coupon, code: "%Old Invalid#code!")
    coupon.save(validate: false)
    coupon.clean_code!
    assert_equal "-Old-Invalid-code!", coupon.code

    coupon = create(:coupon, code: "valid+code")
    coupon.clean_code!
    assert_equal "valid+code", coupon.code
  end

  test "#form_expires_at" do
    moment = Time.parse "October 2, 2012 12:00:00 UTC"
    Timecop.freeze(moment) do
      @coupon.expires_at = moment
      assert_equal "2012-10-02", @coupon.form_expires_at
    end
  end

  test "#applicable_to?" do
    coupon = create(:coupon, plan: "micro", discount: 5)
    assert coupon.applicable_to?(GitHub::Plan.micro)
    refute coupon.applicable_to?(GitHub::Plan.pro)

    coupon = create(:coupon, discount: 5)
    assert coupon.applicable_to?(GitHub::Plan.micro)
    assert coupon.applicable_to?(GitHub::Plan.pro)
  end

  context "#one_hundred_percent_discount?" do
    test "returns false if not 100 percent" do
      coupon = build(:coupon, discount: 0.99)

      refute coupon.one_hundred_percent_discount?

      coupon.discount = 1.1

      refute coupon.one_hundred_percent_discount?
    end

    test "returns true if 100 percent" do
      coupon = build(:coupon, discount: 1.0)

      assert coupon.one_hundred_percent_discount?
    end
  end

  context "#education_coupon?" do
    test "true if the coupon is in an education group" do
      coupon = build(:coupon, group: "education-individual")

      assert coupon.education_coupon?
    end

    test "false if the coupon is not in an education group" do
      coupon = build(:coupon, group: "some-other-group")

      refute coupon.education_coupon?
    end
  end

  context "#redeemable_by" do
    test "site_admins can redeem staff_actor_only coupons" do
      coupon = create :coupon, staff_actor_only: true
      assert coupon.redeemable_by? create(:staff_admin_user)
    end

    test "biztools user can redeem staff_actor_only coupons" do
      coupon = create :coupon, staff_actor_only: true
      assert coupon.redeemable_by? create(:biztools_user)
    end

    test "general users cannot redeem staff_actor_only coupons" do
      coupon = create :coupon, staff_actor_only: true
      refute coupon.redeemable_by? create(:user)
    end
  end

  context "#eligible_accounts" do
    test "general coupon" do
      coupon = create :coupon
      owner = create(:user)
      org_1 = create(:organization, admin: owner, plan: "bronze")
      org_2 = create(:organization, admin: owner, plan: "gold")
      org_3 = create(:organization, admin: owner, plan: "gold",
                                billing_type: "invoice")

      accounts = coupon.eligible_accounts(owner)
      assert_equal 3, accounts.size
      assert accounts.include? owner
      assert accounts.include? org_1
      assert accounts.include? org_2
      refute accounts.include? org_3
    end

    test "individual plan specific" do
      coupon = create :coupon, plan: "micro"
      owner = create(:user)

      accounts = coupon.eligible_accounts(owner)
      assert_equal 1, accounts.size
      assert accounts.include? owner
    end

    test "org plan specific" do
      coupon = create :coupon, plan: "bronze"
      owner = create(:user)
      org_1 = create(:organization, admin: owner, plan: "bronze")
      org_2 = create(:organization, admin: owner, plan: "gold")
      org_3 = create(:organization, admin: owner, plan: "gold",
                                billing_type: "invoice")

      accounts = coupon.eligible_accounts(owner)
      assert_equal 2, accounts.size
      assert accounts.include? org_1
      assert accounts.include? org_2
      refute accounts.include? org_3
    end

    test "doesn't include orgs on the Business plan" do
      coupon = create :coupon
      owner = create(:user)
      org_1 = create(:organization, admin: owner, plan: "gold")
      org_2 = create(:organization, admin: owner, plan: "business_plus")

      accounts = coupon.eligible_accounts(owner)
      assert_equal 2, accounts.size
      assert accounts.include? org_1
      refute accounts.include? org_2
    end

    test "includes enterprise accounts in the coupon initiated state for an Enterprise-plan startup coupon if feature flag is enabled, even if coupon does not have an eligible code name" do
      coupon = create :coupon, group: "startup-program", plan: "business_plus", code: "random-coupon"
      owner = create(:user)
      business_1 = create(:business, :with_self_serve_payment, owners: [owner])
      business_1.initiate_creation_from_coupon
      business_2 = create(:business, :with_self_serve_payment, owners: [owner])
      business_2.initiate_creation_from_coupon
      business_3 = create(:business, :with_self_serve_payment, owners: [owner])
      assert_predicate coupon, :self_serve_business_plus_coupon?

      accounts = coupon.eligible_accounts(owner)
      assert_equal 2, accounts.size
      refute accounts.include? owner
      assert accounts.include? business_1
      assert accounts.include? business_2
      refute accounts.include? business_3
    end

    test "includes both pre-existing and enterprise accounts in the coupon initiated state for an Enterprise-plan startup coupon if coupon_application_for_existing_ea is enabled" do
      enable_feature_flag(:coupon_application_for_existing_ea)

      coupon = create :coupon, group: "startup-program", plan: "business_plus", code: "random-coupon"
      owner = create(:user)
      business_1 = create(:business, :with_self_serve_payment, owners: [owner])
      business_1.initiate_creation_from_coupon
      business_2 = create(:business, :with_self_serve_payment, owners: [owner])
      business_2.initiate_creation_from_coupon
      business_3 = create(:business, :with_self_serve_payment, owners: [owner])
      assert_predicate coupon, :self_serve_business_plus_coupon?

      accounts = coupon.eligible_accounts(owner)
      assert_equal 3, accounts.size
      refute accounts.include? owner
      assert accounts.include? business_1
      assert accounts.include? business_2
      assert accounts.include? business_3
    end

    test "includes organizations for a non-Enterprise-plan startup coupon, and coupon does not have an eligible code name" do
      coupon = create :coupon, group: "startup-program", code: "random-coupon"
      owner = create(:user)
      org_1 = create(:organization, admin: owner, plan: "gold")
      org_2 = create(:organization, admin: owner, plan: "business")

      accounts = coupon.eligible_accounts(owner)
      assert_equal 3, accounts.size
      assert accounts.include? owner
      assert accounts.include? org_1
      assert accounts.include? org_2
    end

    test "includes enterprise accounts in the coupon initiated state for a microsoft enterprise coupon" do
      coupon = create :coupon, group: "microsoft", plan: "business_plus", code: "gfsstartups"
      owner = create(:user)
      business_1 = create(:business, :with_self_serve_payment, owners: [owner])
      business_1.initiate_creation_from_coupon
      business_2 = create(:business, :with_self_serve_payment, owners: [owner])
      business_2.initiate_creation_from_coupon
      business_3 = create(:business, :with_self_serve_payment, owners: [owner])
      assert_predicate coupon, :self_serve_business_plus_coupon?

      accounts = coupon.eligible_accounts(owner)
      assert_equal 2, accounts.size
      refute accounts.include? owner
      assert accounts.include? business_1
      assert accounts.include? business_2
      refute accounts.include? business_3
    end

    test "does not include enterprise accounts that the user is not an owner of" do
      # Make redeeming_user an owner of business_1, billing_manager of business_2, and member of business_3
      # Only business_1 should be returned.
      coupon = create :coupon, group: "microsoft", plan: "business_plus", code: "GitHub-and-Microsoft-Love-Startups-gfs"
      redeeming_user = create(:user)
      business_1 = create(:business, :with_self_serve_payment, owners: [redeeming_user])
      business_1.initiate_creation_from_coupon
      business_2 = create(:business, :with_self_serve_payment, owners: [@user])
      business_2.billing.add_manager(redeeming_user, actor: @user)
      org = create(:organization)
      business_3 = create(:business, owners: [@user], organizations: [org])
      org.add_member(redeeming_user)
      assert_predicate coupon, :self_serve_business_plus_coupon?

      accounts = coupon.eligible_accounts(redeeming_user)
      assert_equal 1, accounts.size
      assert accounts.include? business_1
      refute accounts.include? business_2
      refute accounts.include? business_3
    end

    test "only returns owned businesses that are in the creation_initiated_from_coupon state, if coupon is a self_serve_business_plus_coupon" do
      coupon = create :coupon, group: "microsoft", code: "gfsstartups"
      owner = create :user
      random_business = create :business, owners: [owner]
      coupon_creation_initiated_business = create :business, :with_self_serve_payment, owners: [owner]
      coupon_creation_initiated_business.initiate_creation_from_coupon

      assert_predicate coupon, :self_serve_business_plus_coupon?
      assert_predicate coupon_creation_initiated_business, :creation_initiated_from_coupon?
      refute_predicate random_business, :creation_initiated_from_coupon?

      assert_equal coupon.eligible_accounts(owner), [coupon_creation_initiated_business]
    end

    test "does not return any business accounts if the coupon isn't a self_serve_business_plus_coupon" do
      coupon = create :coupon, group: "community"
      owner = create :user
      random_business = create :business, owners: [owner]
      coupon_creation_initiated_business = create :business, owners: [owner]
      coupon_creation_initiated_business.initiate_creation_from_coupon

      refute_predicate coupon, :self_serve_business_plus_coupon?
      assert_predicate coupon_creation_initiated_business, :creation_initiated_from_coupon?
      refute_predicate random_business, :creation_initiated_from_coupon?

      coupon.eligible_accounts(owner).each do |account|
        refute account.is_a?(Business)  # No business accounts should be included if feature flag is disabled
      end
    end

    test "does not return any business accounts if the user is a billing manager of the business" do
      coupon = create :coupon, group: "microsoft", code: "gfsstartups"
      billing_manager = create :user
      coupon_creation_initiated_business = create :business, owners: [create(:user)]
      coupon_creation_initiated_business.initiate_creation_from_coupon
      coupon_creation_initiated_business.billing.add_manager(billing_manager, actor: coupon_creation_initiated_business.owners.first)

      assert_predicate coupon, :self_serve_business_plus_coupon?
      assert_predicate coupon_creation_initiated_business, :creation_initiated_from_coupon?

      assert_empty coupon.eligible_accounts(billing_manager)
    end
  end

  context "#business_plus_only_coupon?" do
    test "true if the coupon is in BUSINESS_PLUS_GROUP_NAMES" do
      coupon = build(:coupon, group: "sales-serve")

      assert coupon.business_plus_only_coupon?
    end

    test "false if the coupon is not in BUSINESS_PLUS_GROUP_NAMES" do
      coupon = build(:coupon, group: "some-other-group")

      refute coupon.business_plus_only_coupon?
    end
  end
end
