# typed: true
# frozen_string_literal: true

class Billing::Notifications::Dismissal
  attr_reader :account, :actor_id

  def initialize(account:, actor_id:)
    @account = account
    @actor_id = actor_id
  end

  def create(key, product_tag:)
    return unless valid_key?(key) && valid_product?(product_tag)
    Billing::Kv.store.set add_billing_values(key, product_tag), GitHub::Billing.today.to_s,
      expires: 32.days.from_now
  end

  def exists?(key, product_tag:)
    !!Billing::Kv.store.get(add_billing_values(key, product_tag)).value!
  end

  private

  def valid_key?(key)
    # For Billing platform budets, we'll dynamically construct key based on budget info that's not hard-listed
    return true if key.include?("billing_platform")

    Billing::Notifications::AVAILABLE_KEYS.include?(key.to_sym)
  end

  def valid_product?(product_tag)
    # For billing platform, budgets carry the product name and is not hard-listed in dotcom
    return true if product_tag.include?("billing_platform")

    Billing::Notifications::AVAILABLE_PRODUCTS.include?(product_tag)
  end

  def add_billing_values(key, product_tag)
    keys = [key, product_tag, actor_key, account_key, billing_cycle_key]
    keys << budget_key(product_tag) if overage_notice?(key)
    keys.join(".")
  end

  def actor_key
    "actor-#{actor_id}"
  end

  def account_key
    "account-#{account.class.to_s.downcase}-#{account.id}"
  end

  def billing_cycle_key
    "cycle-#{account.current_metered_billing_cycle_starts_at.to_i}"
  end

  def budget_key(product_tag)
    "budget-" + budget_for(product_tag)&.slug.to_s
  end

  def budget_for(product_tag)
    case product_tag
    when Billing::Notifications::SHARED_SPENDING_LIMIT
      shared_budget
    when Billing::Notifications::CODESPACES_SPENDING_LIMIT
      codespaces_budget
    else
      account.budget_for(product: product_tag)
    end
  end

  def codespaces_budget
    account.budget_for(group: :codespaces)
  end

  def shared_budget
    account.budget_for(group: :shared)
  end

  def overage_notice?(key)
    key.include? "spending_limit"
  end
end
