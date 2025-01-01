# typed: true
# frozen_string_literal: true

require "test_helper"

class UserBillingTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    @user = create :credit_card_user, plan: "pro"
    @user_on_micro = create :user, plan: "micro"
    @org = create :organization, admin: @user, plan: "bronze"
    @free_user = create :user, plan: "free"
    @free_org = create :organization, plan: "free"
  end

  test "plan_duration converts humanish strings to an integer representing timespan of a plan in months" do
    assert_equal User.new(plan_duration: "year").plan_duration_in_months, 12
    assert_equal User.new(plan_duration: "month").plan_duration_in_months, 1
  end

  test "#best_plan" do
    @org.stubs(:private_repo_count_for_limit_check).returns(55)
    assert_equal GitHub::Plan.free, @org.best_plan

    @user.stubs(:private_repo_count_for_limit_check).returns(25)
    assert_equal GitHub::Plan.free, @user.best_plan
  end

  test "#best_plan will never return engineyard" do
    @org.stubs(:private_repo_count_for_limit_check).returns(290)
    assert_equal "free", @org.best_plan.name
  end

  test "should bill 12 months on yearly plan" do
    @user.plan_duration = "year"
    assert_equal @user.plan.cost * 12, @user.payment_amount

    @user.redeem_coupon create(:coupon, discount: "25%")
    assert_equal @user.plan.cost * 12 * 0.75, @user.payment_amount
  end

  context "#enable_or_disable!" do
    test "moves user out of disabled if not over plan limit and not over billing attempts limit" do
      user = create(:user, plan: "micro", billing_attempts: 2, billed_on: Date.today)
      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, user: user, amount_in_cents: 1_00, last_status: :settled)
      create(:private_repository, owner: user)
      user.disable!
      user.reload

      user.enable_or_disable!
      assert_equal 1, user.private_repo_count_for_limit_check
      assert !user.disabled
    end

    test "keeps user disabled if very first payment fails" do
      user = create(:user, plan: "micro", billing_attempts: 2)
      create(:private_repository, owner: user)
      user.disable!
      user.reload

      user.enable_or_disable!
      assert_equal 1, user.private_repo_count_for_limit_check
      assert user.disabled
    end

    test "moves user to disabled if over plan limit" do
      user = create(:user, plan: "pro")
      (1..10).each do |i|
        create(:private_repository, owner: user, name: "#{i}-#{Sham.name}")
      end
      user.update(plan: "micro")
      user.disable!
      user.reload

      user.enable_or_disable!
      assert_equal 10, user.private_repo_count_for_limit_check
      assert user.disabled
    end

    test "moves user to disabled if over billing attempts limit" do
      events = subscribe "user.disabled"
      user = create(:user, disabled: false, plan: "micro", billing_attempts: 7)
      user.reload

      user.enable_or_disable!

      expected_payload = {
        user:    user.login,
        user_id: user.id,
        login:   user.login,
        plan:    "micro",
      }

      assert user.disabled
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not create a new transaction if already disabled" do
      user = create(:user, disabled: true, plan: "micro", billing_attempts: 7)
      user.reload

      assert_no_difference "user.transactions.size" do
        user.enable_or_disable!
      end
      assert user.disabled
    end

    test "does not disable an account if the user is on a paid plan but owes nothing" do
      user = create(:user, billing_attempts: 7)
      coupon = create(:coupon, discount: "100%", plan: "small")
      user.redeem_coupon coupon.code
      user.reload
      assert_equal 0, user.payment_amount

      user.enable_or_disable!
      refute user.reload.disabled?
    end

    test "disables an account if the user is on a free plan" do
      user = create(:user, billing_attempts: 7, plan: "free")
      user.reload
      assert_equal 0, user.payment_amount

      user.enable_or_disable!
      assert user.reload.disabled?
    end

    test "disables invalid accounts" do
      user = create(:user, billing_attempts: 7, plan: "micro")
      user.update_attribute :billing_email, "bad_email"
      refute user.reload.valid?

      user.enable_or_disable!
      assert user.reload.disabled?
    end
  end

  test "disable zuora subscription eligible account with data packs" do
    synchronize_github_products_to_zuora
    user = create(:credit_card_user, plan: GitHub::Plan.pro, disabled: false)
    add_as_employee(user)
    user.update_attribute(:gh_role, "staff")

    Asset::Status.create! owner: user, asset_packs: 3
    create :billing_plan_subscription, :zuora, user: user

    user.disable!

    assert user.reload.disabled?
    assert user.zuora_subscription?, "User should still have a plan subscription"
  end

  test "enable braintree subscription eligible account" do
    user = create(:credit_card_user, plan: "micro", disabled: true)

    user.enable!

    refute user.reload.disabled?
  end

  context "#unlock_billing!" do
    test "enables a disabled account" do
      user = create(:user, disabled: true)

      user.unlock_billing!

      assert user.reload.enabled?
    end

    test "enables a disabled organization, even if owned by a Business" do
      org = create :organization, disabled: true
      user = create :user
      business = create :business, owners: [user], organizations: [org]

      assert_predicate org, :disabled?

      org.enable!

      assert_predicate org, :enabled?
      assert_predicate business, :enabled?
    end

    test "enables a disabled organization, even if owned by a disabled Business" do
      org = create :organization, disabled: true
      user = create :user
      business = create :business, owners: [user], organizations: [org]
      business.disable!

      assert_predicate org, :disabled?
      assert_predicate business, :disabled?

      org.enable!

      assert_predicate org, :enabled?
      assert_predicate business, :disabled?  # Business' billing is unaffected
    end

    test "moves the next billing date to 2 days from today" do
      Timecop.freeze("2016-05-01") do
        today = GitHub::Billing.today
        user = create(:user, disabled: true, billed_on: today - 1.week)

        user.unlock_billing!

        assert_equal today + 2.days, user.reload.billed_on
      end
    end

    test "resets the billing attempts" do
      user = create(:user, disabled: true, billing_attempts: 3)

      user.unlock_billing!

      assert user.reload.billing_attempts.zero?
    end

    test "does not change billing date if it's already in the future" do
      Timecop.freeze("2016-05-01") do
        today = GitHub::Billing.today
        user = create :user, disabled: true, billed_on: today + 1.week

        user.unlock_billing!

        assert_equal today + 1.week, user.reload.billed_on
      end
    end

    test "does not modify billing date if there's a plan subscription" do
      Timecop.freeze("2016-05-01") do
        today = GitHub::Billing.today

        user = create :user,
          plan: "pro",
          disabled: true,
          billed_on: today

        create(:billing_plan_subscription, user: user)

        user.unlock_billing!

        assert_equal today, user.reload.billed_on
      end
    end
  end

  context "per-seat pricing" do
    test "users always have 1 filled_seat" do
      user = create(:user)
      assert_equal 1, user.filled_seats
      assert_equal 0, user.available_invitable_seats
    end

    test "organizations have 1 or more filled_seats" do
      org = create :organization, plan: "business", seats: 5
      assert_equal 1, org.filled_seats
      assert_equal 20, org.filled_seats_percent
      assert_equal 4, org.available_invitable_seats

      4.times { org.add_member create(:user) }

      assert_equal 5, org.filled_seats # 3 including owner
      assert_equal 100, org.filled_seats_percent
      assert_equal 0, org.available_invitable_seats
    end

    test "organizations delegate to business seat count when business is present" do
      business = create :business, seats: 10
      org = create :organization, seats: 5, business: business
      other_org = create :organization, seats: 5, business: business
      org.reload
      assert_equal 2, org.filled_seats
      assert_equal 20, org.filled_seats_percent
      assert_equal 8, org.available_invitable_seats

      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
        2.times { org.add_member create(:user) }
        3.times { other_org.add_member create(:user) }
      end

      org.reload
      assert_equal 7, org.filled_seats # both org owners + 5 other members added
      assert_equal 70, org.filled_seats_percent
      assert_equal 3, org.available_invitable_seats
    end

    test "handles organizations that are owned by businesses with all bundled licenses" do
      user = create(:user)
      business = create(:business, :volume_licensed)
      organization = create(:organization, admin: user, business: business)
      organization.reload # reload to get business membership loaded
      business.update_columns(seats: 0)

      # one consumed seat out of an available 0
      assert_equal 1, organization.filled_seats
      assert_equal 100, organization.filled_seats_percent

      create(:licensing_bundled_license_assignment, business: business, user: user)

      organization.reload
      # zero consumed seats out of an available 0
      assert_equal 0, organization.filled_seats
      assert_equal 0, organization.filled_seats_percent
    end

    test "only outside collaborators on private repositories count toward seats" do
      org = create :organization, plan: "business", seats: 5
      2.times { org.add_member create(:user) }
      public_repository = create(:public_repository, owner: org)
      private_repository = create(:private_repository, owner: org)
      public_repository.add_member(create(:user))
      private_repository.add_member(create(:user))

      assert_equal 2, org.outside_collaborators.size
      assert_equal 1, org.collaborators_on_private_repositories.size
      assert_equal 4, org.filled_seats # 4 including owner and private outside collaborator
    end

    test "outside collaborators on private forks that are removed do not count toward seats" do
      org = create :organization, plan: "business", seats: 5
      org.allow_private_repository_forking(actor: org.admins.first)
      2.times { org.add_member create(:user) }
      private_repository = create(:private_repository, owner: org, from_example: :simple)
      private_repository.add_member(create(:user))
      private_repository.add_member(forker = create(:user))
      private_fork = create(:fork_repository, forker: forker, fork_repo: private_repository)
      private_fork.add_member create(:user)
      only = [RemoveUserFromRepoCleanupJob, OrganizationCollaboratorBackfillJob]
      perform_enqueued_jobs(only: only) do
        private_repository.remove_member forker
      end

      assert_equal 1, org.outside_collaborators.size
      assert_equal 1, org.outside_collaborators(include_forks: false).size
      assert_equal 1, org.collaborators_on_private_repositories.size
      assert_equal 4, org.filled_seats # 5 including owner, 2 team members, and 1 outside(one is the forker)
    end

    test "outside collaborators on private forks do not count toward seats" do
      org = create :organization, plan: "business", seats: 5
      org.allow_private_repository_forking(actor: org.admins.first)
      2.times { org.add_member create(:user) }
      private_repository = create(:private_repository, owner: org, from_example: :simple)
      private_repository.add_member(create(:user))
      private_repository.add_member(forker = create(:user))
      private_fork = create(:fork_repository, forker: forker, fork_repo: private_repository)
      private_fork.add_member create(:user)

      assert_equal 3, org.outside_collaborators.size # this includes the fork member
      assert_equal 2, org.outside_collaborators(include_forks: false).size
      assert_equal 2, org.collaborators_on_private_repositories.size
      assert_equal 5, org.filled_seats # 5 including owner, 2 team members, and 2 outside(one is the forker)
    end

    test "outside collaborators on mulitple private repositories are only counted once" do
      org = create :organization, plan: "business", seats: 5
      2.times { org.add_member create(:user) }
      private_repository_1 = create(:private_repository, owner: org)
      private_repository_2 = create(:private_repository, owner: org)
      outside_collaborator = create(:user)
      private_repository_1.add_member(outside_collaborator)
      private_repository_2.add_member(outside_collaborator)
      assert_equal 4, org.filled_seats
    end

    test "outside collaborators with invites are only counted once" do
      org   = create :organization, plan: "business", seats: 5
      admin = create(:user)
      org.add_member admin, action: :admin
      private_repository_1 = create(:private_repository, owner: org)
      private_repository_2 = create(:private_repository, owner: org)
      outside_collaborator = create(:user)
      private_repository_1.add_member(outside_collaborator)
      private_repository_2.add_member(outside_collaborator)
      org.invite outside_collaborator, inviter: admin
      assert_equal 3, org.filled_seats
    end

    test "outside collaborators invited by email are all counted" do
      # n.b. This explicitly tests *two* invitees with nil user_ids
      #      because we had a bug that only counted the first one
      org   = create :organization, plan: "business", seats: 5
      admin = create(:user)
      org.add_member admin, action: :admin
      private_repository_1 = create(:private_repository, owner: org)
      private_repository_2 = create(:private_repository, owner: org)
      outside_collaborator = create(:user)
      private_repository_1.add_member(outside_collaborator)
      private_repository_2.add_member(outside_collaborator)
      org.invite outside_collaborator, inviter: admin
      org.invite nil, inviter: admin, email: "alice@example.com"
      org.invite nil, inviter: admin, email: "bob@example.com"
      assert_equal 5, org.filled_seats
    end

    test "does not count billing managers" do
      user = create(:user)
      org  = create :organization, plan: "business", seats: 5
      org.billing.add_manager(user, actor: org.admins.first)
      org.reload
      assert_equal 1, org.filled_seats
    end

    test "does not count invited billing managers" do
      user  = create(:user)
      admin = create(:user)
      org  = create :organization, plan: "business", seats: 5
      org.add_member admin, action: :admin
      org.invite user, inviter: admin, role: :billing_manager
      org.reload
      assert_equal 2, org.filled_seats
    end

    test "does count invited admins" do
      user  = create(:user)
      admin = create(:user)
      org  = create :organization, plan: "business", seats: 5
      org.add_member admin, action: :admin
      org.invite user, inviter: admin, role: :admin
      org.reload
      assert_equal 3, org.filled_seats
    end

    test "organizations know how many seats are needed to make a repository private" do
      org = create :organization, plan: "business", seats: 6 # 1 member (owner)
      4.times { org.add_member create(:user) } # 5 members

      owner = org.admins.first
      org.invite(create(:user), inviter: owner, role: :billing_manager)
      org.billing.add_manager(create(:user), actor: owner)

      public_repository = create(:public_repository, owner: org)
      2.times { public_repository.add_member create(:user) }
      assert_equal 1, org.seats_needed_for_collaborators_on(public_repository)

      private_repository = create(:private_repository, owner: org)
      private_collaborator = create(:user)
      private_repository.add_member private_collaborator # 6 members
      assert_equal 0, org.seats_needed_for_collaborators_on(private_repository)

      public_repository.add_member(private_collaborator)
      assert_equal 2, org.seats_needed_for_collaborators_on(public_repository)
      org.update_attribute(:seats, 8)
      assert public_repository.reload.toggle_visibility(actor: owner) # 8 members
      assert_equal 0, org.seats_needed_for_collaborators_on(public_repository)
    end

    test "organizations default to maximum number of seats" do
      org = create :organization, plan: "bronze", seats: 3
      team = create :team, organization: org

      assert_equal 3, org.seats
      assert_equal 1, org.filled_seats
      assert_equal 3, org.default_seats

      5.times { team.add_member create(:user) }

      assert_equal 6, org.default_seats
    end

    test "user default seats includes all private repository collaborators" do
      user = create(:user, plan: "pro")
      repository = create(:private_repository, owner: user)

      assert_equal 0, user.seats
      assert_equal 1, user.filled_seats
      assert_equal 1, user.default_seats

      6.times { repository.add_member(create(:user)) }

      assert_equal 7, user.default_seats
    end

    test "seat count cannot be less than organization member count" do
      org = create :organization, plan: "business", seats: 6
      team = create :team, organization: org
      5.times { team.add_member(create(:user)) }

      org.seats = 5
      refute org.save

      assert_includes org.errors.full_messages.join, "must be at least the number of currently filled seats"

      org.seats = 7
      assert org.save
    end

    test "seat count should be no more than the world population" do
      org = create :organization, plan: "business", seats: 5
      org.seats = 10_000_000_001
      refute org.save
      assert_match /no more than the total number of people on Planet Earth/, org.errors.full_messages.to_sentence
      org.seats = 4_000_000
      assert org.save
    end

    test "seat count is not validated if there's an associated business because the business owns the seat count" do
      business = create(:business, seats: 3)

      admin = create(:user)
      member = create(:user)
      org = create(:business_plus_organization, seats: 2, admins: [admin])
      org.add_member(member)

      business.add_organization(org)
      org.reload # make organization aware of business

      org.seats = 1

      assert org.valid?
    end
  end

  context "tiered per-seat pricing" do
    test "organization needs at least the plan's base number of seats" do
      org = Organization.new \
              login: "muan",
              billing_email: "muan@example.com",
              admin: create(:user),
              plan: "business",
              seats: 1

      assert org.valid?
    end
  end

  test "#enable" do
    user = create(:user, disabled: true)
    user.enable!

    refute user.disabled
    transaction = user.transactions.last
    assert transaction
    assert_equal "enabled", transaction.action
  end

  test "should be charged if billed_on is nil" do
    @user.billed_on = nil
    assert @user.past_due?
  end

  test "should be charged if billed_on is in the past" do
    @user.billed_on = GitHub::Billing.today - 5.days
    assert @user.past_due?
  end

  test "should be charged if billed_on is today" do
    @user.billed_on = GitHub::Billing.today
    assert @user.past_due?
  end

  test "should not be charged if billed_on is in the future" do
    @user.billed_on = GitHub::Billing.today + 5.days
    refute @user.past_due?
  end

  test "should not be charged if user is on the free plan" do
    @user.plan = "free"
    @user.billed_on = GitHub::Billing.today

    refute @user.past_due?
  end

  context "#beneficiary?" do
    test "true if user should be charged but isn't" do
      user = create :user, plan: "pro"
      assert user.beneficiary?
    end

    test "false if user has a coupon redemption" do
      user = create :user, plan: "pro"
      coupon = create :coupon
      user.redeem_coupon(coupon)
      refute user.beneficiary?
    end

    test "true if user has a partial coupon redemption" do
      user = create :user, plan: "pro"
      coupon = create :coupon, :percentage
      user.redeem_coupon(coupon)
      assert user.payment_amount > 0
      assert user.beneficiary?
    end

    test "true if user has an expired coupon redemption" do
      user = create :user, plan: "pro"
      coupon = create :coupon
      coupon_redemption = user.redeem_coupon(coupon)
      coupon_redemption.expire
      coupon_redemption.save
      assert user.reload.beneficiary?
    end

    test "false if user has a valid payment method" do
      user = create(:credit_card_user, plan: "pro")
      refute user.beneficiary?
    end

    test "false if user is on a free plan" do
      user = create :user, plan: "free"
      refute user.beneficiary?
    end

    test "false if user has no payment amount" do
      user = create :user, plan: "free_with_addons"
      refute user.beneficiary?
    end

    test "false for an enterprise owned organization with a valid payment method on the ent account and past due" do
      business = create(:business, :with_credit_card)
      create(:business_organization_membership, business: business)
      organization = business.organizations.first
      refute_nil organization

      # Simulate business past due its billing date
      business.customer.update(billing_end_date: GitHub::Billing.today - 2.days)
      # Delegated to the business attributes we just validate the beneficiary assumption
      assert_predicate organization, :past_due?

      refute_predicate organization, :beneficiary?
    end
  end

  test "100% coupon for an individual with previous billing history skips end-of-month adjustment" do
    # Scenario: User was previously billed on the Jan 29, but now it's
    # February 28 and they have a coupon. Their next billed_on date should be
    # March 29, not 28.
    coupon = create :coupon, limit: 3, duration: 120

    create :billing_transaction, user: @user_on_micro,
      transaction_type: "first-time-paid-upgrade",
      last_status: :settled

    Timecop.freeze(2013, 12, 29, 14) do
      GitHub::Billing.redeem_coupon_and_charge @user_on_micro, coupon
      assert_equal Date.new(2014, 1, 29), @user_on_micro.billed_on
    end

    Timecop.freeze(2014, 1, 29, 13) do
      result = @user_on_micro.recurring_charge
      assert result.success?
      assert_equal Date.new(2014, 2, 28), @user_on_micro.billed_on
    end
  end

  context "#billing_trouble?" do
    test "for a free user" do
      @user.plan = "free"
      assert !@user.billing_trouble?

      @user.billing_attempts = 3
      assert !@user.billing_trouble?
    end

    test "for a paid user" do
      assert !@user.billing_trouble?

      @user.billing_attempts = 3
      assert @user.billing_trouble?
    end

    test "for a paid user with a 100% coupon" do
      @user.billing_attempts = 3
      coupon = create(:coupon, discount: "100%", plan: "small")
      @user.redeem_coupon coupon.code

      assert !@user.billing_trouble?
    end

    test "for a paid user with a 50% off coupon" do
      @user.billing_attempts = 3
      coupon = create(:coupon, discount: "50%")
      @user.redeem_coupon coupon.code

      assert @user.billing_trouble?
    end
  end

  context "#org_billing_trouble?" do
    test "an untroubled org" do
      assert_equal [], @user.billing_troubled_orgs
      assert !@user.org_billing_trouble?
    end

    test "a troubled org" do
      @org.billing_attempts = 3
      @org.save

      assert_equal [@org], @user.billing_troubled_orgs
      assert @user.org_billing_trouble?
    end
  end

  context "#org_in_billing_trouble?" do
    test "an untroubled org" do
      assert_equal [], @user.billing_troubled_orgs
      refute @user.org_in_billing_trouble?(org: @org)
    end

    test "a troubled org" do
      @org.billing_attempts = 3
      @org.save

      assert_equal [@org], @user.billing_troubled_orgs
      assert @user.org_in_billing_trouble?(org: @org)
    end
  end

  context "#payment_amount" do
    test "monthly plan" do
      user = create(:user, plan: "small")
      assert_equal 12, user.payment_amount
    end

    test "yearly plan" do
      user = create(:user, plan: "small", plan_duration: User::BillingDependency::YEARLY_PLAN)
      assert_equal 144, user.payment_amount
    end

    test "monthly plan with a $ off discount" do
      user = create(:user, plan: "small")
      coupon = create(:coupon, discount: "7")
      user.redeem_coupon(coupon)
      assert_equal GitHub::Plan.pro, user.plan
      assert_equal 0, user.payment_amount
    end

    test "monthly plan with an expiring $ off discount upgrades user but does not discount after expiration" do
      user = create(:user, plan: "small", billed_on: GitHub::Billing.today + 1.month)

      coupon = create(:coupon, discount: GitHub::Plan.pro.cost, duration: 14)
      user.redeem_coupon(coupon)
      assert_equal GitHub::Plan.pro, user.plan
      assert_equal user.plan.cost, user.payment_amount
    end

    test "monthly plan with a plan-specific discount" do
      user = create(:user, plan: "small")
      coupon = create(:coupon, discount: "100%", plan: "small")
      user.redeem_coupon(coupon)
      assert_equal 0, user.payment_amount
    end

    test "query a plan with a different duration" do
      user = create(:user, plan: "small")
      assert_equal 144, user.payment_amount(duration_in_months: 12)
    end

    test "query pro plan with a different duration" do
      user = create :user, plan: GitHub::Plan.pro, plan_duration: "month"
      assert_equal GitHub::Plan.pro.yearly_cost, user.payment_amount(duration_in_months: 12)
    end

    test "query another plan while on a monthly plan" do
      user = create(:user, plan: "small")
      assert_equal 50, user.payment_amount(plan: GitHub::Plan.find("large"))
    end

    test "query another plan while on a monthly plan with a coupon" do
      user = create(:user, plan: "small")
      coupon = create(:coupon, discount: "7")
      user.redeem_coupon(coupon)
      assert_equal 43, user.payment_amount(plan: GitHub::Plan.find("large"))
    end

    test "query another plan while on a monthly plan with a plan-specific coupon" do
      user = create(:user, plan: "small")
      coupon = create(:coupon, plan: "small")
      user.redeem_coupon(coupon)
      assert_equal 50, user.payment_amount(plan: GitHub::Plan.find("large"))
    end

    test "query another plan while on a monthly plan and specifying seats" do
      org = create(:organization, plan: "gold", seats: 0)

      # because base units is 1, we add 1 extra seat than before (which was 5)
      assert_equal 8, org.payment_amount(plan: GitHub::Plan.business, plan_seats: 2)
    end

    test "business plan" do
      org = create(:organization, plan: "business", plan_duration: "year", seats: 6)

      assert_equal 288, org.payment_amount
    end

    test "business monthly plan" do
      org = create(:organization, plan: "business", seats: 6)

      assert_equal 24, org.payment_amount
    end

    test "coupons can be applied to business plans" do
      org = create(:organization, plan: "business", plan_duration: "year", seats: 10)

      assert_equal 480, org.payment_amount

      org.redeem_coupon create(:coupon, discount: "50", plan: "business")

      # TODO make this test work again AKA > 0
      assert_equal 0, org.reload.payment_amount
    end

    test "accepts a seat count" do
      org = create :organization, plan: "business"

      assert_equal 80, org.payment_amount(plan_seats: 20)
    end
  end

  context "#payment_difference" do
    test "can apply the balance when calculating" do
      Timecop.freeze(2015, 4, 10) do
        user = create(:user, :zuora, plan: :small, billed_on: GitHub::Billing.today + 10.days)
        create(:billing_plan_subscription, :zuora, user: user)
        user.reload
        difference = Billing::Money.new((22 - 12) * (9 / 31.0) * 100).dollars
        assert_equal difference, user.payment_difference(GitHub::Plan.medium)

        user.plan_subscription.balance_in_cents = -1_00
        assert_equal difference - 1.00, user.payment_difference(GitHub::Plan.medium, use_balance: true)
      end
    end

    test "uses the default seat count if one isn't provided" do
      org = create :organization, plan: :business, seats: 6

      assert_equal 102, org.payment_difference(GitHub::Plan.business_plus, seat_count: nil)
    end
  end

  context "#in_yearly_grace_period?" do
    test "returns true for a yearly user that hasn't been billed yet for the year" do
      # current plan ends in 15 days but user has changed to yearly
      grace_ends = GitHub::Billing.today + 15.days
      user = create(:user,
        plan: "small",
        plan_duration: "year",
        billed_on: grace_ends,
      )
      # last transaction is monthly
      create(:billing_transaction,
        user: user,
        plan_name: "small",
        renewal_frequency: :monthly,
        amount_in_cents: 7_00,
        service_ends_at: grace_ends,
      )
      assert user.in_yearly_grace_period?
    end

    test "returns false for a yearly user that has been billed" do
      # current plan ends in 15 days
      service_ends = GitHub::Billing.today + 15.days
      user = create(:user,
        plan: "small",
        plan_duration: "year",
        billed_on: service_ends,
      )
      # last transaction is yearly
      create(:billing_transaction,
        user: user,
        plan_name: "small",
        renewal_frequency: :yearly,
        amount_in_cents: 7_00,
        service_ends_at: service_ends,
      )
      refute user.in_yearly_grace_period?
    end

    test "returns false for a yearly user with recently failed billing" do
      # user has 1 failed billing attempt, will be attempt again in 1 day
      user = create(:user,
        plan: "small",
        plan_duration: "year",
        billed_on: GitHub::Billing.today + 1.day,
        billing_attempts: 1,
      )
      # last transaction is failed yearly
      create(:billing_transaction,
        user: user,
        plan_name: "small",
        renewal_frequency: :yearly,
        amount_in_cents: 7_00,
        service_ends_at: GitHub::Billing.today + 1.year - 1.day,
        last_status: :processor_declined,
      )
      refute user.in_yearly_grace_period?
    end

    test "returns false for a monthly user" do
      user = create :user, plan_duration: "month"
      refute user.in_yearly_grace_period?
    end

    test "returns false if moving away from the free plan" do
      user = create(:user, plan: "free")
      user.plan_duration = "year"
      user.plan = "small"
      refute user.in_yearly_grace_period?
    end
  end

  context "#recurring_charge" do
    test "transitions to an external subscription if eligible" do
      user = create(:credit_card_user, plan: "pro")

      assert user.has_valid_payment_method?

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user, purpose: nil, skip_sync: false)
        .returns({ success: true })

      assert user.recurring_charge.success?
    end

    test "does not transition to external subscription if missing valid payment method" do
      staff = create :no_credit_card_user
      add_as_employee(staff)
      staff.update_attribute(:gh_role, "staff")

      GitHub::Billing.redeem_coupon_and_charge staff,
        create(:coupon, discount: 20, duration: 10)

      GitHub::Billing.expects(:transition_to_external_subscription).never

      staff.recurring_charge
    end

    test "manually retries a charge for a dunning subscription" do
      user = create :credit_card_user, billing_attempts: 1
      plan_subscription = create :billing_plan_subscription, :zuora, user: user

      GitHub.zuorest_client.expects(:create_invoice_collect).once.returns({ success: true })

      assert user.recurring_charge.success?
    end

    test "returns success for a current subscription" do
      user = create :credit_card_user
      plan_subscription = create :billing_plan_subscription, :zuora, user: user
      assert user.recurring_charge.success?
    end
  end

  context "#has_credit_card?" do
    test "returns false for a user without a braintree vault customer" do
      user = create(:user)
      refute user.has_credit_card?
    end

    test "returns false for a user with a vault customer and no credit card" do
      @user.customer.payment_method.destroy
      refute @user.reload.has_credit_card?
    end

    test "returns true for a user with a vault customer and credit card" do
      assert @user.has_credit_card?
    end
  end

  context "#remove_all_payment_methods" do
    test "removes all credit cards" do
      VCR.use_cassette("zuora/remove_all_payment_methods") do
        zuora_account_id = "2c92c0fa61789dac01619105be872892"
        @user.customer.payment_method.update payment_processor_customer_id: zuora_account_id
        assert @user.remove_all_payment_methods(@user)
        refute @user.reload.has_credit_card?
      end
    end

    test "works without a payment_method" do
      user = create(:user)
      assert_nil user.remove_all_payment_methods(@user)
      refute user.has_credit_card?
    end
  end

  test "#paid_plan?" do
    assert @user.paid_plan?
    refute @free_user.paid_plan?
    assert @org.paid_plan?
    refute @free_org.paid_plan?
  end

  test "#paid_non_trial_plan?" do
    trial_org = create(:organization, plan: "business_plus")
    billing_plan_trial = create(:billing_plan_trial, :active, user: trial_org)

    assert trial_org.paid_plan?
    refute trial_org.paid_non_trial_plan?

    assert @org.paid_non_trial_plan?
    refute @free_org.paid_non_trial_plan?
    assert @user.paid_non_trial_plan?
    refute @free_user.paid_non_trial_plan?
  end
end

# These tests need to run whether or not billing is enabled, since some of this
# code is called in enterprise too.
class MoreUserBillingTest < GitHub::TestCase
  fixtures do
    @free_user = create :user, plan: "free"
    @free_org  = create :organization, plan: "free"
    @user      = create :user, plan: "micro"
    @org       = create :organization, plan: "bronze"

    if GitHub.enterprise?
      @enterprise_user = create :user, plan: "enterprise"
      @enterprise_org = create :organization, plan: "enterprise"
    end
  end

  test "#plan_supports?(:repos, visibility: :private)" do
    assert @user.plan_supports?(:repos, visibility: :private)
    assert @free_user.plan_supports?(:repos, visibility: :private)
    assert @org.plan_supports?(:repos, visibility: :private)

    if GitHub.enterprise?
      assert @enterprise_user.plan_supports?(:repos, visibility: :private)
      assert @enterprise_org.plan_supports?(:repos, visibility: :private)
    end
  end

  test "#can_add_private_repo?" do
    assert @free_user.can_add_private_repo?
    assert @user.can_add_private_repo?

    @user.stubs(:at_private_repo_limit?).returns(true)
    refute @user.can_add_private_repo?

    assert @org.can_add_private_repo?
    assert @free_org.can_add_private_repo?

    if GitHub.enterprise?
      assert @enterprise_user.can_add_private_repo?
      assert @enterprise_org.can_add_private_repo?
    end
  end

  test "Enterprise orgs need 0 free seats" do
    if GitHub.enterprise?
      org = create :organization, plan: "enterprise"
      2.times { org.add_member create(:user) }

      owner = org.admins.first

      public_repository = create(:public_repository, owner: org)
      2.times { public_repository.add_member create(:user) }
      assert_equal 0, org.seats_needed_for_collaborators_on(public_repository)
    end
  end

  context "#private_repo_by_default?" do
    if GitHub.enterprise?
      test "true for users by default" do
        assert_predicate @free_user, :private_repo_by_default?
        assert_predicate @user, :private_repo_by_default?
      end

      test "true for orgs by default" do
        assert_predicate @org, :private_repo_by_default?
        assert_predicate @free_org, :private_repo_by_default?
      end

      test "true for orgs when default visibility is private" do
        GitHub.stubs(:default_repo_visibility).returns("private")
        assert_predicate @org, :private_repo_by_default?
        assert_predicate @free_org, :private_repo_by_default?
      end

      test "true for users when default visibility is private" do
        GitHub.stubs(:default_repo_visibility).returns("private")
        assert_predicate @user, :private_repo_by_default?
        assert_predicate @free_user, :private_repo_by_default?
      end

      test "true for orgs when default visibility is internal" do
        GitHub.stubs(:default_repo_visibility).returns("internal")
        assert_predicate @org, :private_repo_by_default?
        assert_predicate @free_org, :private_repo_by_default?
      end

      test "true for users when default visibility is internal" do
        GitHub.stubs(:default_repo_visibility).returns("internal")
        assert_predicate @user, :private_repo_by_default?
        assert_predicate @free_user, :private_repo_by_default?
      end

      test "false for orgs when default visibility is public" do
        GitHub.stubs(:default_repo_visibility).returns("public")
        refute_predicate @org, :private_repo_by_default?
        refute_predicate @free_org, :private_repo_by_default?
      end

      test "false for users when default visibility is public" do
        GitHub.stubs(:default_repo_visibility).returns("public")
        refute_predicate @user, :private_repo_by_default?
        refute_predicate @free_user, :private_repo_by_default?
      end
    else
      test "false for users" do
        refute_predicate @free_user, :private_repo_by_default?
        refute_predicate @user, :private_repo_by_default?
      end

      test "true for paid orgs"  do
        assert_predicate @org, :private_repo_by_default?
      end

      test "true for free orgs" do
        assert_predicate @free_org, :private_repo_by_default?
      end
    end
  end

  context "#undiscounted_payment_amount" do
    test "ignores discounts when calculating cost" do
      @user.plan_duration = "year"
      assert_equal @user.plan.cost * 12, @user.undiscounted_payment_amount

      @user.redeem_coupon create(:coupon, discount: "25%")
      assert_equal @user.plan.cost * 12, @user.undiscounted_payment_amount
      refute_equal @user.undiscounted_payment_amount, @user.payment_amount
    end

    test "accepts a duration argument when calculating price" do
      assert_equal @user.plan.cost * 12, @user.undiscounted_payment_amount(duration: :year)
    end
  end

  context "#undiscounted_payment_difference" do
    test "doesn't include discounts when checking price difference" do
      user = create :user, :zuora, plan: GitHub::Plan.pro, billed_on: GitHub::Billing.today + 1.month
      user.redeem_coupon create :coupon, discount: 1

      assert_equal (-1 * user.plan.cost), user.undiscounted_payment_difference(GitHub::Plan.free)
    end
  end
end
