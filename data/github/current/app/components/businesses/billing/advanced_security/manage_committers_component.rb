# typed: true
# frozen_string_literal: true

class Businesses::Billing::AdvancedSecurity::ManageCommittersComponent < ApplicationComponent
  EMDASH = "\u{2014}"

  sig { returns Business }
  attr_reader :business

  sig { returns User }
  attr_reader :user

  sig { params(business: Business, user: User).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end

  private

  memoize def can_manage_seats?
    @business.adminable_by?(current_user)
  end

  memoize def advanced_security_seats
    business.advanced_security_seats_for_entity
  end

  memoize def active_advanced_security_seats
    business.advanced_security_license.consumed_seats
  end

  memoize def new_seats
    new_seats = params[:seats] || advanced_security_seats
    [[new_seats.to_i, minimum_seat_count].max, maximum_seat_count].min
  end

  memoize def payment_due
    return EMDASH if new_seats <= advanced_security_seats
    business.advanced_security_price(seats: (new_seats - advanced_security_seats)).format
  end

  memoize def minimum_seat_count
    [1, active_advanced_security_seats, advanced_security_seats - ::Billing::ChangeSubscription::MAX_SEAT_DELTA].max
  end

  memoize def maximum_seat_count
    advanced_security_seats + ::Billing::ChangeSubscription::MAX_SEAT_DELTA
  end

  memoize def new_seats_payment
    business.advanced_security_price(seats: new_seats).format
  end

  memoize def current_payment
    business.advanced_security_price(seats: advanced_security_seats).format
  end

  memoize def cost_per_committer
    "#{business.advanced_security_price(seats: 1).format} / month"
  end

  memoize def next_payment
    business.advanced_security_subscription_item&.next_billing_date&.strftime("%B %-e, %Y")
  end

  memoize def payment_due_notice
    if new_seats < advanced_security_seats
      "Your changes will take effect on #{next_payment}"
    elsif new_seats == advanced_security_seats
      ""
    else
      "Your next payment of #{new_seats_payment} will be due on #{next_payment}"
    end
  end
end
