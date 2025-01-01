# typed: strict
# frozen_string_literal: true

module Couponable
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern
  # Shared couponable logic for Users, Organizations and Enterprises

  sig { returns(T.nilable(String)) }
  attr_accessor :new_coupon_code

  class_methods do
    extend T::Sig
    # Sends emails and activates in-site notices for accounts that have a coupon
    # that is going to expire in two weeks. You should only run this once per
    # day.
    sig { returns(T::Array[String]) }
    def notify_coupon_expiring_in_two_weeks
      T.bind(self, T.any(T.class_of(::User), T.class_of(::Business)))

      usernames = []
      CouponRedemption.of_billable_entity_type(self.to_s).expiring_in_two_weeks.find_each do |cr|
        billable_entity = cr.billable_entity
        next if billable_entity.nil? || cr.coupon.nil?
        next if !billable_entity.paid_plan?

        if billable_entity.user?
          T.cast(billable_entity, User).activate_notice!(:coupon_will_expire)
        end

        BillingNotificationsMailer.coupon_will_expire_soon(billable_entity, cr).deliver_later
        usernames << billable_entity.display_login
      end
      usernames
    end

    sig { returns(T::Array[String]) }
    def notify_coupon_expiring_in_one_week
      T.bind(self, T.any(T.class_of(::User), T.class_of(::Business)))

      usernames = []
      CouponRedemption.of_billable_entity_type(self.to_s).expiring_in_one_week.find_each do |cr|
        billable_entity = cr.billable_entity
        next if billable_entity.nil? || cr.coupon.nil?
        next if !billable_entity.paid_plan?

        if billable_entity.user?
          T.cast(billable_entity, User).activate_notice!(:coupon_will_expire)
        end

        BillingNotificationsMailer.coupon_will_expire_soon(billable_entity, cr).deliver_later
        usernames << billable_entity.display_login
      end
      usernames
    end
  end

  included do
    T.bind(self, T.any(T.class_of(::User), T.class_of(::Business)))

    has_many :coupon_redemptions,
      -> { T.unsafe(self).active.order("coupon_redemptions.id DESC") },
      dependent: :destroy,
      as: :billable_entity

    has_many :expired_coupons,
      -> { T.unsafe(self).expired },
      class_name: "CouponRedemption",
      as: :billable_entity

    has_many :coupons, -> { order("coupons.id DESC") }, through: :coupon_redemptions

    class NonUniqueBillableEntityTypesError < RuntimeError; end

    # Public: The active coupon. Only one coupon can be active at a time.
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of User or Business records, prefill it this way:
    #
    #   # Execute 1 query to preload (usually in a controller action):
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :coupon)
    #
    #   users.each do |user|
    #     # Method is preloaded and memoized -- no queries are executed here!
    #     user.coupon
    #   end
    #
    # Returns a Coupon if one is active. Returns nil if no coupons are active.
    batch_method :coupon do |billable_entities|
      new_coupon_codes = billable_entities.map(&:new_coupon_code).compact.to_set
      billable_entity_types = billable_entities.map { |entity| entity.class.polymorphic_name }.uniq
      raise NonUniqueBillableEntityTypesError.new(billable_entity_types) if billable_entity_types.size > 1

      billable_entity_type = billable_entity_types.first
      billable_entity_ids = billable_entities.map(&:id)

      coupon_redemptions = CouponRedemption.arel_table
      latest_coupon_redemptions_subquery = coupon_redemptions
        .where(coupon_redemptions[:billable_entity_id].in(billable_entity_ids)
        .and(coupon_redemptions[:billable_entity_type].eq(billable_entity_type))
          .and(coupon_redemptions[:expired].eq(false))
        )
        .group(:billable_entity_id, :billable_entity_type)
        # project is same as select in active record ( i think )
        .project(
          coupon_redemptions[:coupon_id].maximum.as("latest_coupon_id"),
          coupon_redemptions[:billable_entity_id].as("coupon_redemption_billable_entity_id"),
          coupon_redemptions[:billable_entity_type].as("coupon_redemption_billable_entity_type"),
        )

      join_type = new_coupon_codes.any? ? "LEFT OUTER JOIN" : "INNER JOIN"
      coupons = Coupon.joins(
        "#{join_type} (#{latest_coupon_redemptions_subquery.to_sql}) AS latest_coupon_redemptions " \
        "ON latest_coupon_redemptions.latest_coupon_id = coupons.id"
      ).select(
        "coupons.*, latest_coupon_redemptions.coupon_redemption_billable_entity_id, latest_coupon_redemptions.coupon_redemption_billable_entity_type")
      if new_coupon_codes.any?
        coupons = coupons.where("latest_coupon_redemptions.latest_coupon_id IS NOT NULL OR coupons.code IN (?)",
          new_coupon_codes)
      end
      coupons = coupons.to_a

      new_coupons_by_code = if new_coupon_codes.any?
        coupons.select { |coupon| new_coupon_codes.include?(coupon.code) }.index_by(&:code)
      else
        {}
      end

      latest_redeemed_coupons_by_billable_entity = coupons
        .select do |coupon|
          coupon[:coupon_redemption_billable_entity_id].present? &&
            coupon[:coupon_redemption_billable_entity_type].present?
        end.map do |coupon|
          [
            [coupon[:coupon_redemption_billable_entity_id], coupon[:coupon_redemption_billable_entity_type]],
            coupon
          ]
        end.to_h

      billable_entities.each_with_object({}) do |billable_entity, hash|
        hash[billable_entity] = new_coupons_by_code[billable_entity.new_coupon_code] || latest_redeemed_coupons_by_billable_entity[[billable_entity.id, billable_entity.class.polymorphic_name]]
      end
    end

    # Public: The active coupon's redemption for this user.  The redemption
    # will tell us how long the coupon is active for, when the user
    # redeemed it, and so on.
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of User records, prefill it this way:
    #
    #   # Execute 1 query to preload (usually in a controller action):
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)
    #
    #   users.each do |user|
    #     # Method is preloaded and memoized -- no queries are executed here! user.coupon_redemption
    #   end
    #
    # Returns a CouponRedemption if a coupon is active.
    # Returns nil if no coupon is active.
    batch_method :coupon_redemption do |billable_entities|
      persisted_billable_entities = billable_entities.reject(&:new_record?)
      GitHub::PrefillAssociations.prefill_batch_method(persisted_billable_entities, :coupon)

      coupon_redemptions_by_billable_entity = {}
      billable_entities_with_coupons = persisted_billable_entities.select { |entity| entity.coupon.present? }
      if billable_entities_with_coupons.any?
        base_redemptions_query = CouponRedemption.active
        billable_entity = billable_entities_with_coupons.first
        coupon_redemptions = base_redemptions_query.for_billable_entity(billable_entity).for_coupon(billable_entity.coupon)
        billable_entities_with_coupons.drop(1).each do |billable_entity|
          coupon_redemptions = coupon_redemptions.or(
            base_redemptions_query.for_billable_entity(billable_entity).for_coupon(billable_entity.coupon)
          )
        end
        coupon_redemptions_by_billable_entity = coupon_redemptions.index_by do |redemption|
          [redemption.billable_entity_id, redemption.billable_entity_type]
        end
      end

      billable_entities.each_with_object({}) do |billable_entity, hash|
        hash[billable_entity] = if billable_entity.new_record? || billable_entity.coupon.nil?
          nil
        else
          coupon_redemptions_by_billable_entity[[billable_entity.id, billable_entity.class.polymorphic_name]]
        end
      end
    end
  end

end
