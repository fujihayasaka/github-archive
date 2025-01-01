# typed: true
# frozen_string_literal: true

module Resiliency
  module Responses
    class WillPaginateCollection < Response
      def initialize(&block)
        collection = WillPaginate::Collection.create(1, 1, 0) do |pager|
          pager.replace([])
        end
        super(collection)
      end
    end
  end
end
