# typed: strict
# frozen_string_literal: true

class BillingJob < ApplicationJob
  queue_as :billing

  # Don't enqueue billing jobs unless billing is enabled
  around_enqueue do |_job, block|
    block.call if GitHub.billing_enabled?
  end
end
