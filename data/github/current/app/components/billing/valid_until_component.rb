# typed: strict
# frozen_string_literal: true

module Billing # rubocop:disable Rails/ModuleNaming
  class ValidUntilComponent < ApplicationComponent
    sig { returns(Date) }
    attr_reader :expiration_date

    sig { returns(T.nilable(Time)) }
    attr_reader :renewal_scheduled_start_datetime

    sig { returns(T::Boolean) }
    attr_reader :has_renewal

    sig { params(expiration_date: (Date), renewal_scheduled_start_datetime: T.nilable(Time), has_renewal: T::Boolean).void }
    def initialize(expiration_date:, renewal_scheduled_start_datetime:, has_renewal:)

      @expiration_date = expiration_date
      @renewal_scheduled_start_datetime = renewal_scheduled_start_datetime
      @has_renewal = has_renewal
    end

    sig { returns(T::Boolean) }
    def expired?
      return false if @expiration_date.nil?
      @expiration_date < GitHub::Billing.today
    end

    sig { returns(T::Boolean) }
    def has_renewal?
      @has_renewal
    end

    sig { returns(String) }
    def expiration_date_formatted
      # the react component doesn't show a 0 in front of the day of the month
      # removing the 0 from the day of the month
      @expiration_date.strftime("%B %-d, %Y")
    end

    sig { returns(T.nilable(String)) }
    def renewal_scheduled_start_datetime_formatted
      return nil if @renewal_scheduled_start_datetime.nil?
      @renewal_scheduled_start_datetime.strftime("%B %-d, %Y")
    end
  end
end
