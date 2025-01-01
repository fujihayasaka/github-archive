# typed: strict
# frozen_string_literal: true

class Billing::Signup

  include ActiveModel::Validations

  sig { returns(User) }
  attr_accessor :user

  sig { returns(User) }
  attr_accessor :actor

  sig { returns(T.nilable(GitHub::Plan)) }
  attr_reader :plan

  validates :plan, presence: { message: "was not found" }

  validate :user_is_persisted_and_valid
  validate :ensure_no_billing_record_on_user
  with_options if: -> { T.cast(self, Billing::Signup).plan.present? } do
    validate :plan_is_paid
    validate :plan_is_eligible_for_user_type
    validate :user_can_change_to_plan
  end

  sig do
    params(
      user: User,
      plan_name: String,
      actor: User,
    ).void
  end
  def initialize(user:, plan_name:, actor:)
    @user = user
    @plan = T.let(GitHub::Plan.find(plan_name), T.nilable(GitHub::Plan))
    @actor = actor
  end

  sig { returns(T::Boolean) }
  def customer_already_exists?
    ensure_no_billing_record_on_user

    errors.of_kind?(:user, :already_signed_up)
  end

  private

  sig { void }
  def user_is_persisted_and_valid
    if user.new_record? || user.invalid?
      errors.add(:user)
    end
  end

  sig { void }
  def ensure_no_billing_record_on_user
    if user.has_billing_record?
      errors.add(:user, :already_signed_up, message: "has already signed up")
    end
  end

  sig { void }
  def plan_is_paid
    if T.must(plan).free?
      errors.add(:plan, :not_paid, message: "must not be free for sign up")
    end
  end

  sig { void }
  def plan_is_eligible_for_user_type
    plan = T.must(self.plan)
    if user.user? && plan.orgs?
      errors.add(:plan, :invalid_plan_type_for_user, message: "#{plan.display_name} cannot be used for users")
    elsif user.organization? && !plan.orgs?
      errors.add(:plan, :invalid_plan_type_for_user, message: "#{plan.display_name} cannot be used for organizations")
    end
  end

  sig { void }
  def user_can_change_to_plan
    plan = T.must(self.plan)
    if !plan.per_seat? && !user.can_change_plan_to?(plan, actor: actor)
      errors.add(:plan, :invalid_plan_for_user, message: "#{plan} cannot be used for user sign up")
    end
  end
end
