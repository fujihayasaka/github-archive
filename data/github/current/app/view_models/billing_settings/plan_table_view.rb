# typed: true
# frozen_string_literal: true

module BillingSettings
  class PlanTableView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::NumberHelper
    include MoneyHelper

    attr_reader :coupon, :selected_account, :selected_plan, :request

    def discounted_plan_pricing(account, plan)
      discounted_price = Billing::Pricing.new(
        account: account,
        plan: plan,
        seats: account.default_seats,
        coupon: coupon,
      ).discounted

      if discounted_price > 0
        "#{money(discounted_price)}/#{account.plan_duration}"
      else
        "Free"
      end
    end

    # Returns plans that this account is eligible for.  Does not offer the
    # free plan, does not include plans where the account exceeds the number
    # private repos allowed, starts at the largest plan the coupon can get for
    # free, if any.
    #
    # account - User or Organization to find plans for
    #
    # Returns and Array of Plans
    def plans_for(account)
      return [] unless account.billable?

      plans = unfiltered_plans_for(account)

      # don't include plans where the account exceeds private repos allowed
      private_repo_count = account.private_repo_count_for_limit_check
      plans.reject! { |plan| plan.repos < private_repo_count }

      if coupon
        if coupon.plan
          plans.select! { |plan| plan == coupon.plan  }
        else
          # don't try to apply a coupon for a free plan unless this is an
          # account currently being transformed from user to organization, or a
          # legacy percentage-off coupon that is not plan specific. In these
          # cases we don't want to force selection of a paid plan,
          unless (coupon.percentage? && !coupon.plan_specific?) || account.new_record?
            plans.reject! { |plan| plan.free? }
          end

          # start at the largest plan they can get for free
          first_free_index = plans.index do |plan|
            plan_price(plan: plan, account: account, discount: coupon.discount).to_f <= 0
          end
          plans = plans[0..first_free_index] unless first_free_index.nil?
        end
      end

      # if the current plan is redeemable but not one of the 6 cheapest redeemable plans,
      # we show the current plan, 1 more expensive plan, and 4 cheaper plans
      current_plan_index = plans.index(account.plan)
      if current_plan_index && !plans.last(6).include?(account.plan)
        start = current_plan_index == 0 ? 0 : current_plan_index - 1
        plans[start..start + 5]
      else
        plans.last(6)
      end
    end

    def plan_table_data(account)
      %(data-has-billing="#{account.has_valid_payment_method?}" data-login="#{account.display_login}").html_safe # rubocop:disable Rails/OutputSafety
    end

    # Public: Constructs data- attributes for plan choices; used for analytics
    #
    # account - A User object
    # plan    - A GitHub::Plan object
    #
    # Returns a string
    def plan_row_data(account, plan)
      data = []
      data << %(data-name="#{plan.name}")

      plan_cost = Billing::Pricing.new(
        plan: plan,
        seats: account.default_seats,
        discount: coupon&.discount,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
      ).discounted

      data << %(data-cost="#{(plan_cost * 100).to_i}")
      data.join(" ").html_safe # rubocop:disable Rails/OutputSafety
    end

    # Returns the most sensible user id for a given coupon.
    #
    # user   - User that is redeeming the coupon
    # coupon - Da Coupon
    #
    # Returns a user id as a String
    def default_user_id(user, coupon)
      if coupon.user_only?
        user.id.to_s
      else
        ""
      end
    end

    def plan_selected(account, plan)
      "selected" if selected_plan == plan && selected_account == account
    end

    def plan_name(plan)
      if plan.org_plan? && plan.name == "free"
        "Open Source"
      elsif plan.unlimited?
        "Unlimited private repositories"
      else
        plan.display_name.capitalize
      end
    end

    def coupon_plan
      @coupon_plan ||= coupon.plan if coupon
    end

    def per_seat_pricing_model(account, coupon, new_plan: nil)
      ::Billing::PlanChange::PerSeatPricingModel.new \
        account,
        seats: account.default_seats,
        plan_duration: account.plan_duration,
        new_plan: new_plan,
        coupon: (coupon if coupon.applicable_to?(new_plan || GitHub::Plan.business))
    end

    def enterprise_account_pricing_model(business, coupon)
      Billing::Pricing.new(
        account: business,
        plan: GitHub::Plan.business_plus,
        plan_duration: business.plan_duration,
        plan_annual_discount: business.annual_discount_allowed?,
        seats: business.default_seats,
        coupon: coupon,
      )
    end

    def per_seat_pricing_model_renewal_price(account, coupon)
      Billing::Pricing.new(
        account: account,
        plan: GitHub::Plan.business, # n.b. Billing::PlanChange::PerSeatPricingModel#initialize
        plan_duration: account.plan_duration,
        seats: account.default_seats,
        coupon: coupon,
      ).discounted
    end

    def unlimited_plan_for_account(account)
      if account.organization?
        GitHub::Plan.business
      else
        GitHub::Plan.pro
      end
    end

    private

    def plan_price(plan:, account:, discount: nil)
      Billing::Pricing.new(
        account: account,
        plan: plan,
        seats: account.default_seats,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        discount: discount,
      ).discounted
    end

    def unfiltered_plans_for(account)
      if account.organization?
        [GitHub::Plan.business, GitHub::Plan.free]
      else
        [GitHub::Plan.pro, GitHub::Plan.free]
      end
    end
  end
end
