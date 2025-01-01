# typed: true
# frozen_string_literal: true

module Billing
  # Quacks like a User, if the user isn't around anymore
  class DeadUser
    extend T::Sig

    attr_accessor :id, :login, :billing_email,
      :billing_extra, :created_at, :user_type, :vat_code

    alias :email :billing_email
    alias :to_s :login

    sig { void }
    def initialize
      yield self if block_given?
    end

    sig { returns T::Boolean }
    def organization?
      user_type == "organization"
    end

    sig { returns T::Boolean }
    def user?
      user_type == "user"
    end

    sig { params(feature: T.any(String, Symbol)).returns(T::Boolean) }
    def feature_enabled?(feature)
      GitHub.flipper[feature].enabled?
    end

    sig { returns T::Boolean }
    def sponsors_invoiced?
      false
    end

    sig { returns T.nilable(String) }
    def type
      user_type
    end

    sig { returns T.nilable(String) }
    def time_zone_name
      nil
    end

    sig { returns T::Array[Billing::DeadUser] }
    def billing_users
      [self]
    end

    sig { returns ActiveRecord::Relation }
    def billing_external_emails
      BillingExternalEmail.none
    end

    sig { returns T::Array[UserEmail] }
    def emails
      []
    end

    sig { returns T::Boolean }
    def no_verified_emails?
      true
    end

    sig { returns T.nilable(GitHub::Plan) }
    def plan
      nil
    end

    sig { returns T.nilable(String) }
    def plan_name
      nil
    end

    sig { returns T.nilable(::Billing::PlanSubscription) }
    def plan_subscription
      nil
    end

    sig { returns String }
    def billing_account_type
      type.to_s.capitalize
    end

    sig { returns T.nilable(String) }
    def display_login
      User.to_display_login(@login)
    end

    sig { returns T.nilable(String) }
    def last_ip
      nil
    end

    sig { returns T.nilable(String) }
    def trade_screening_status
      nil
    end
  end
end
