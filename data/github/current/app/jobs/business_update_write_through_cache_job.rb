# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The BusinessBackgroundCacheJob job will update the business cache for a given method.
class BusinessUpdateWriteThroughCacheJob < ApplicationJob
  queue_as :business_update_write_through_cache

  retry_on_dirty_exit

  resolve_tenant_context do |_, business|
    business
  end

  locked_by timeout: 1.minute, key: ->(job) {
    "#{job.arguments[1].id}:#{job.arguments[0]}"
  }

  def perform(lock_key, business, method, args, type, pluck)
    business.write_through_cache.update(method, args, type: type, pluck: pluck)
  end
end
