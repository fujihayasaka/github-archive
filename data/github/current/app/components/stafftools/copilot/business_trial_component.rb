# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::BusinessTrialComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(Copilot::Organization) }
  attr_reader :organization

  sig { returns(T.nilable(Copilot::BusinessTrial)) }
  attr_reader :business_trial

  sig { returns(T::Boolean) }
  attr_reader :has_copilot_seats

  sig do
    params(
      organization: ::Organization,
      business_trial: T.nilable(Copilot::BusinessTrial),
    ).void
  end
  def initialize(organization, business_trial)
    @organization   = T.let(Copilot::Organization.new(organization), Copilot::Organization)
    @business_trial = business_trial
    @cloud_trial    = T.let(::Billing::EnterpriseCloudTrial.new(organization), Billing::EnterpriseCloudTrial)
    @has_copilot_seats = T.let(Copilot::SeatAssignment.for_organization(@organization.organization_object).any?, T::Boolean)
  end

  sig { returns(T::Boolean) }
  def render?
    !@organization.organization_object.spammy?
  end

  sig { returns(T::Boolean) }
  def organization_trial_active?
    (business&.trial?) || @cloud_trial.active?
  end

  sig { returns(T.nilable(::Business)) }
  def business
    @organization.organization_object.business
  end

  sig { returns(T.nilable(Copilot::Business)) }
  memoize def copilot_business
    return nil unless business.present?
    Copilot::Business.new(T.must(business))
  end

  sig { returns(T::Boolean) }
  def can_force_upgrade?
    business_trial&.can_force_upgrade? || false
  end

  sig { returns(Integer) }
  def trial_duration
    if @cloud_trial.active?
      @cloud_trial.days_remaining
    else
      if business&.trial?
        T.must(business).trial_days_remaining
      else
        30
      end
    end
  end

  sig { returns(Integer) }
  def member_count
    @organization.organization_object.member_ids.count
  end

  sig { returns(Integer) }
  def used_seat_count
    Copilot::Seat.for_organization(@organization.organization_object).count
  end

  sig { returns(T::Boolean) }
  def can_be_converted_to_copilot_enterprise_trial?
    return false unless business_trial.present?
    return false if business&.digital_front_door?

    T.must(business_trial).can_be_converted_to_copilot_enterprise_trial?
  end

  sig { returns(T::Array[T::Array[String]]) }
  memoize def trial_options
    options = []
    options << ["Copilot Business", "business"]

    return options if business&.digital_front_door?

    options << ["Copilot Enterprise", "enterprise"]
    options
  end
end
