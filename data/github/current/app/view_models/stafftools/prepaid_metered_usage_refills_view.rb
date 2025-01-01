# typed: true
# frozen_string_literal: true

module Stafftools
  class PrepaidMeteredUsageRefillsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :owner, :page

    delegate :current_page, :total_count, :total_entries, :total_pages, to: :raw_refills

    def refills
      @refills ||= raw_refills.map { |refill| RefillDecorator.new(refill) }
    end

    private

    def raw_refills
      @raw_refills ||= ::Billing::PrepaidMeteredUsageRefill.where(owner: owner).order(expires_on: :desc).page(page)
    end

    class RefillDecorator
      attr_reader :refill

      delegate :id, :zuora_rate_plan_charge_id, :staff_created?, to: :refill

      def initialize(refill)
        @refill = refill
      end

      def formatted_amount
        ::Billing::Money.new(
          refill.amount_in_subunits,
          refill.currency_code,
        ).format
      end
    end
    private_constant :RefillDecorator
  end
end
