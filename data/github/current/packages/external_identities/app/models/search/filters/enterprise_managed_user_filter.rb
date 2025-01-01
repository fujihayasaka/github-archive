# typed: true
# frozen_string_literal: true

module Search
  module Filters

    class EnterpriseManagedUserFilter < ::Search::Filter
      def initialize(opts = {})
        @options = opts
        @business_id = options.fetch(:business_id, nil)
        @valid = true
      end

      def build(values)
        return if values.blank?
        values
      end

      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        if @business_id.nil?
          @bool_collection.must_not = { exists: { field: :business_id } }
        else
          @bool_collection.must = { term: { business_id: @business_id  } }
        end

        @bool_collection
      end
    end
  end  # Filter
end  # Search
