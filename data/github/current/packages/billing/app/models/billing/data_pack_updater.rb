# typed: true
# frozen_string_literal: true

#
# This class is responsible for updating the number of data packs associated with a given target (user or business). The
# class has several constants defined that set the boundaries for the number of data packs that can be added/associated
# to a target as a whole or per request/call.
#
module Billing
  class DataPackUpdater
    MINIMUM_PACKS = 0
    MAXIMUM_PACKS = 10000
    MAXIMUM_PACKS_PER_REQUEST = 100
    attr_reader :error

    def initialize(target, total_packs:, actor:)
      @target = target
      @total_packs = total_packs
      @delta_packs = total_packs - target.data_packs
      @actor = actor
    end

    def update
      if valid?
        data_pack_change.asset_status.update_data_packs(quantity: total_packs, actor: actor)
        true
      else
        false
      end
    end

    private

    attr_reader :target, :total_packs, :delta_packs, :actor

    def valid?
      result = target.validate_purchases_allowed(actor: actor)
      if delta_packs.positive? && result.failed?
        @error = result.error_message
      elsif delta_packs.positive? && delta_packs > MAXIMUM_PACKS_PER_REQUEST
        @error = "Oops, please enter a quantity of data packs less than #{MAXIMUM_PACKS_PER_REQUEST}"
      elsif total_packs < MINIMUM_PACKS || total_packs > MAXIMUM_PACKS # Totally arbitrary limit
        @error = "Oops, please enter a quantity of data packs between 0 and #{MAXIMUM_PACKS}."
      elsif target.in_a_sales_managed_business?
        @error = "Please contact your GitHub Enterprise account representative to add more data packs to your plan."
      elsif target.needs_valid_payment_method_to_buy_data_packs?(total_packs)
        @error = "Please add a payment method to your account."
      end

      @error.nil?
    end

    def data_pack_change
      @_data_pack_change ||= Billing::PlanChange::DataPackChange.new(
        target,
        total_packs: total_packs,
      )
    end
  end
end
