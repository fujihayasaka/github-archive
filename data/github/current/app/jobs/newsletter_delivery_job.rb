# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class NewsletterDeliveryJob < ApplicationJob
  queue_as :newsletter_delivery

  schedule interval: 1.hour
  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    NewsletterSubscription.start_delivery(type: "vulnerability")
  end
end
