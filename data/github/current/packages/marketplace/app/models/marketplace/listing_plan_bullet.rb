# typed: true
# frozen_string_literal: true

class Marketplace::ListingPlanBullet < ApplicationRecord::Domain::Integrations
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  self.table_name = "marketplace_listing_plan_bullets"

  BULLET_LIMIT_PER_LISTING_PLAN = 4

  # rubocop:todo Rails/InverseOf
  belongs_to :listing_plan, class_name: "Marketplace::ListingPlan",
                            foreign_key: "marketplace_listing_plan_id"
  # rubocop:enable Rails/InverseOf

  validates :listing_plan, :value, presence: true
  validates :value, unicode3: true, allow_blank: true
  validates :value, uniqueness: { scope: :marketplace_listing_plan_id, case_sensitive: false }, if: -> { T.unsafe(self).errors[:value].blank? }
  validate :not_at_bullet_limit

  # Public: Returns true if this bullet can be edited by the given User.
  def allowed_to_edit?(actor)
    listing_plan && T.unsafe(listing_plan).allowed_to_edit?(actor)
  end

  def platform_type_name
    "MarketplaceListingPlanBullet"
  end

  private

  def not_at_bullet_limit
    return unless listing_plan

    bullets = T.unsafe(listing_plan).bullets
    bullets = bullets.where("id <> ?", id) if persisted?

    if bullets.count >= BULLET_LIMIT_PER_LISTING_PLAN
      errors.add(:listing_plan, "has reached its limit for bullet points.")
    end
  end
end
