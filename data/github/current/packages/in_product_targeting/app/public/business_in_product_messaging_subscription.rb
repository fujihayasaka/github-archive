# typed: strict
# frozen_string_literal: true

class BusinessInProductMessagingSubscription < ApplicationRecord::Domain::InProductTargeting
  belongs_to :business
  # In-product targeting does not run on Proxima (multi-tenant enterprise) or GHES, and the
  # in_product_targeting database/table is not provisioned there. Skip enqueuing the background
  # destroy job in those environments so business purging doesn't fail querying a missing table.
  destroy_in_background_with :business,
    run_if: ->(_business) { !GitHub.single_or_multi_tenant_enterprise? }

  validates :business_id, presence: true, uniqueness: true
  validates :promotion_subscribed, inclusion: { in: [true, false] }
  validates :tip_subscribed, inclusion: { in: [true, false] }
  validates :members_request_subscribed, inclusion: { in: [true, false] }
end
