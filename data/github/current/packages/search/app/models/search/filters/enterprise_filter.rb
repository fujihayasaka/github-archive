# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class EnterpriseFilter < ::Search::Filter
      class EnterpriseFilterError < StandardError; end

      attr_reader :field, :enterprise_ids

      def initialize(opts = {})
        super(opts)
        @field = :_id
        @enterprise_ids = Array(opts[:enterprise_ids])

        if blank?
          raise EnterpriseFilterError, "Cannot filter by enterprise without enterprise ids"
        end
      end

      def blank?
        @enterprise_ids.blank?
      end

      def must
        return if blank?
        # Return the properly formatted terms filter
        { terms: { field.to_s => enterprise_ids } }
      end

      def should; end
      def must_not; end
    end
  end
end
