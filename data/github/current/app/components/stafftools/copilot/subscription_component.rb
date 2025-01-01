# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::SubscriptionComponent < ApplicationComponent
  extend T::Sig
  attr_reader :user, :subscription, :has_trial_subscription, :subscription_type, :days_left_on_free_trial

  def initialize(user, subscription, has_trial_subscription, any_orgs_using_cfb: false)
    @user                    = user
    @subscription            = subscription
    @has_trial_subscription  = has_trial_subscription
    @subscription_type       = subscription.present? ? subscription.interval.to_s.capitalize : "None"
    @days_left_on_free_trial = subscription.present? ? subscription.days_left_on_free_trial : 0
    @any_orgs_using_cfb      = any_orgs_using_cfb
  end

  sig { returns(T::Boolean) }
  def render?
    !@any_orgs_using_cfb
  end
end
