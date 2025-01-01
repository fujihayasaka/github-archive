# typed: true
# frozen_string_literal: true

module ApplicationController::CustomerCategoryDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def customer_category_instrumentation
    return unless response.status > 0
    tags = {
      controller: controller_name_with_namespace,
      action: action_name,
      customer_category: customer_category,
      status_range: GitHub::TaggingHelper.status_range(response.status)
    }
    GitHub.dogstats.increment("customer_category.request.count", tags: tags)
    start_time = request.env["process.request_start"]
    return if start_time.blank?
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("customer_category.request.duration", elapsed, tags: tags)
  end

  def customer_category
    respond_to?(:current_organization) && send(:current_organization)&.customer_category || "none"
  end

  def customer_size
    respond_to?(:current_organization) && send(:current_organization)&.customer_category_size || 0
  end
end
