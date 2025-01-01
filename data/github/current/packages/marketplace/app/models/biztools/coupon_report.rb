# typed: true
# frozen_string_literal: true

module Biztools
  class CouponReport

    def initialize(coupon)
      @coupon = coupon
    end

    def generate
      CSV.generate do |csv|
        csv << [
          "Account type",
          "Login",
          "Name",
          "Location",
          "Members",
          "Private repositories",
          "Public repositories",
          "Redeemed on",
        ]

        redemptions.each do |redemption|
          account = redemption.billable_entity
          csv << [
            account.type,
            account.login,
            account.profile.try(:name),
            account.profile.try(:location),
            members[account.id] || 0,
            private_repositories[account.id] || 0,
            public_repositories[account.id] || 0,
            redemption.created_at.try(:to_date),
          ]
        end
      end
    end

    private

    attr_reader :coupon

    def redemptions
      @redemptions ||= coupon.coupon_redemptions.active.includes(:billable_entity).where(billable_entity_type: "User")
    end

    def organization_redemptions
      @organization_redemptions ||= redemptions.select { |redemption| redemption.billable_entity.organization? }
    end

    def members
      @members ||= Ability.where(
        actor_type: "User",
        priority: Ability.priorities[:direct],
        subject_type: "Organization",
        subject_id: organization_redemptions.map(&:billable_entity_id),
      ).group(:subject_id).count(:all)
    end

    def private_repositories
      @private_repositories ||= Repository.private_scope.where(
        owner_id: redemptions.map(&:billable_entity_id),
      ).group(:owner_id).count(:all)
    end

    def public_repositories
      @public_repositories ||= Repository.public_scope.where(
        owner_id: redemptions.map(&:billable_entity_id),
      ).group(:owner_id).count(:all)
    end
  end
end
