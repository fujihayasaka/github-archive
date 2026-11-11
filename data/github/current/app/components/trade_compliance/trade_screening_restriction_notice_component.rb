# typed: strict
# frozen_string_literal: true

module TradeCompliance
  class TradeScreeningRestrictionNoticeComponent < ApplicationComponent
    sig { returns(Billing::Types::Account) }
    attr_reader :target

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.nilable(String)) }
    attr_reader :title

    sig { returns(T::Boolean) }
    attr_reader :check_for_current_user

    sig { returns(T::Boolean) }
    attr_reader :hide_title

    sig { returns(Symbol) }
    attr_reader :feature_type

    sig { returns(T.nilable(String)) }
    attr_reader :class_name

    sig do
      params(
        target: Billing::Types::Account,
        title: String,
        check_for_current_user: T::Boolean,
        hide_title: T::Boolean,
        description: T.nilable(String),
        class_name: T.nilable(String),
        feature_type: Symbol,
      ).void
    end
    def initialize(
      target:,
      title:,
      check_for_current_user: false,
      hide_title: false,
      description: nil,
      class_name: nil,
      feature_type: :default
    )
      @target = target
      @title = title
      @description = description
      @check_for_current_user = check_for_current_user
      @hide_title = hide_title
      @class_name = class_name
      @feature_type = feature_type
    end

    sig { returns(T::Boolean) }
    def render?
      return true if target.has_commercial_interaction_restriction?(feature_type: feature_type)

      check_for_current_user && current_user.has_commercial_interaction_restriction?(feature_type: feature_type)
    end
  end
end
