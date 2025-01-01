# typed: strict
# frozen_string_literal: true

# A legacy model that predates the audit log and is primarily used to hold audit
# log style information about changes to billing plans. Also provides very
# inaccurate information about revenue.
class Transaction < ApplicationRecord::Domain::Users
  extend T::Sig

  PAID_CONDITIONS = T.let([
    "action = 'upgraded'",
    "action = 'downgraded'",
    "(action = 'signed-up' and current_plan <> 'free')",
    "(action = 'deleted' and current_plan <> 'free')",
  ], T::Array[String])

  PAID_AND_SWITCH_CONDITIONS = T.let(PAID_CONDITIONS + [
    "action = 'switched-to-yearly'",
  ], T::Array[String])

  SPONSORS_ACTIONS = T.let(%w(sp_added sp_cancelled sp_changed).freeze, T::Array[String])

  enum :current_subscribable_type, [Marketplace::ListingPlan.name, SponsorsTier.name, Billing::ProductUUID.name], suffix: true
  enum :old_subscribable_type, [Marketplace::ListingPlan.name, SponsorsTier.name, Billing::ProductUUID.name], suffix: true

  belongs_to  :user
  belongs_to  :billing_transaction, class_name: "Billing::BillingTransaction"
  belongs_to  :current_subscribable, polymorphic: true
  belongs_to  :old_subscribable, polymorphic: true
  before_save :set_fields

  scope :paid, -> {
    conditions = PAID_CONDITIONS.join(" or ")
    where(conditions)
  }

  scope :paid_and_switch, -> {
    conditions = PAID_AND_SWITCH_CONDITIONS.join(" or ")
    where(conditions)
  }

  scope :lost, -> {
    conditions = [
      "action = 'downgraded'",
      "(action = 'deleted' and current_plan <> 'free')",
      "(action = 'disabled' and current_plan <> 'free')",
    ].join(" or ")

    where(conditions)
  }

  scope :upgrades, -> { where(action: "upgraded") }

  scope :for_subscribables, -> (subscribables) {
    where(current_subscribable: subscribables).or(where(old_subscribable: subscribables))
  }

  scope :yearly, -> { where(plan_duration: "year") }

  scope :sponsors_actions, -> { where(action: SPONSORS_ACTIONS) }

  scope :sponsors_tier_actions, ->(tiers) {
    for_subscribables(tiers).sponsors_actions.order(timestamp: :desc)
  }

  sig { returns(T.nilable(String)) }
  attr_accessor :old_plan_duration
  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_accessor :params

  sig { params(args: T.untyped).void }
  def initialize(*args)
    @params = T.let(args.first || {}, T::Hash[Symbol, T.untyped])
    super
  end

  sig { returns(T.nilable(GitHub::Plan)) }
  def current_plan
    GitHub::Plan.find(super, account: user)
  end

  sig { returns(T.nilable(GitHub::Plan)) }
  def old_plan
    GitHub::Plan.find(super, account: user)
  end

  sig { returns(Integer) }
  def seat_delta
    current_seats - old_seats
  end

  sig { returns(Integer) }
  def old_data_packs
    asset_packs_total - asset_packs_delta
  end

  # Human compatible output for current plan name
  # Safe to use with plans that are no longer in the system like 'ey'
  sig { returns(T.nilable(String)) }
  def human_current_plan
    if current_plan = self.current_plan
      current_plan.display_name.humanize
    end
  end

  sig { returns(T.nilable(String)) }
  def humanized_action
    case action
    when "downgraded", "upgraded" then "Changed"
    when "sp_added" then "New sponsorship"
    when "sp_cancelled" then "Cancelled sponsorship"
    when "sp_changed" then "Sponsorship tier changed"
    when "sub_created" then "Subscription created"
    when "sub_cancelled" then "Subscription cancelled"
    when "sub_changed" then "Subscription changed"
    else
      action&.humanize
    end
  end

  sig { returns(T::Boolean) }
  def org?
    !!user.try(:organization?)
  end

  sig { returns(T.nilable(String)) }
  def username
    user.try(:login)
  end

  private

  sig { void }
  def set_fields
    user = self.user
    return unless user
    self.current_plan = user.plan.try(:name)
    self.current_seats = user.seats
    self.plan_duration = user.plan_duration
    self.next_billed_on = user.billed_on
    self.timestamp ||= Time.current
    self.action ||= determine_action
  end

  sig { returns(T.nilable(String)) }
  def determine_action
    if params[:action].present? # action specified
      params[:action]
    elsif params[:old_plan].present? # change in plan
      current_plan_cost = current_plan.try(:cost) || 0
      old_plan_cost = GitHub::Plan.find(params[:old_plan]).try(:cost) || 0
      current_plan_cost > old_plan_cost ? "upgraded" : "downgraded"
    elsif params[:old_plan_duration].present? # change in plan duration
      "switched-to-#{plan_duration}ly"
    elsif params[:old_seats].present? # change in seats
      current_seats > params[:old_seats] ? "added_seats" : "removed_seats"
    elsif params[:asset_packs_delta].present? # change in data packs
      asset_packs_total > old_data_packs ? "added_asset_packs" : "removed_asset_packs"
    end
  end
end
