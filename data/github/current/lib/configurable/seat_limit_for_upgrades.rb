# typed: strict
# frozen_string_literal: true

module Configurable
  module SeatLimitForUpgrades
    extend T::Sig
    extend T::Helpers

    KEY = "custom_seat_limit_for_upgrades"
    ADVANCED_SECURITY_KEY = "custom_seat_limit_for_upgrades_advanced_security"
    TRANSACTIONS_KEY = "custom_seat_limit_for_transactions"

    DEFAULT_SEAT_LIMIT_FOR_UPGRADES = 1000
    DEFAULT_SEAT_LIMIT_FOR_TRANSACTIONS = 300

    requires_ancestor { Configurable }

    # Public: Get an org's limit on the maximum number of seats that can be
    #         added during a self-serve plan upgrade.
    sig { returns(Integer) }
    def seat_limit_for_upgrades
      custom_seat_limit_for_upgrades || default_seat_limit_for_upgrades
    end

    # Public: Get the custom limit for an org on the maximum number of seats
    #         that can be added during a self-serve plan upgrade.
    sig { returns(T.nilable(Integer)) }
    def custom_seat_limit_for_upgrades
      config.int(KEY)
    end

    # Public: Remove the custom limit for an org on the maximum number of seats
    #         that can be added during a self-serve plan upgrade.
    sig { params(actor: User).returns(T::Boolean) }
    def delete_custom_seat_limit_for_upgrades(actor)
      config.delete(KEY, actor)
    end

    # Public: Set a custom limit for an org on the maximum number of seats
    #         that can be added during a self-serve plan upgrade.
    sig { params(value: Integer, actor: User).returns(T::Boolean) }
    def set_custom_seat_limit_for_upgrades(value, actor)
      config.set!(KEY, value, actor)
    end

    # Public: Returns the default seat limit for self-serve plan upgrades
    sig { returns(Integer) }
    def default_seat_limit_for_upgrades
      DEFAULT_SEAT_LIMIT_FOR_UPGRADES
    end

    ## Advanced Security
    sig { returns(Integer) }
    def seat_limit_for_advanced_security_upgrade
      custom_seat_limit_for_advanced_security_upgrade || default_seat_limit_for_upgrades
    end

    sig { returns(T.nilable(Integer)) }
    def custom_seat_limit_for_advanced_security_upgrade
      config.int(ADVANCED_SECURITY_KEY)
    end

    sig { params(value: Integer, actor: User).returns(T::Boolean) }
    def set_custom_seat_limit_for_advanced_security_upgrades(value, actor)
      config.set!(ADVANCED_SECURITY_KEY, value, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def delete_custom_seat_limit_for_advanced_security_upgrade(actor)
      config.delete(ADVANCED_SECURITY_KEY, actor)
    end
  end
end
