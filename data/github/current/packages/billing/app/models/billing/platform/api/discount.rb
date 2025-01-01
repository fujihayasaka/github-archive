# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class Discount
        include ActiveModel::Model

        attr_accessor :sku, :discount
      end
    end
  end
end
