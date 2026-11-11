# typed: strict
# frozen_string_literal: true

class CreateZuoraProductJob < ApplicationJob
  queue_as :zuora

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(product: Coupon).void }
  def perform(product)
    product.sync_to_zuora
  end
end
