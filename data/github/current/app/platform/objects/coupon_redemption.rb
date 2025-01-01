# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CouponRedemption < Platform::Objects::Base
      description "A user's coupon redemption."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal
      minimum_accepted_scopes %w(site_admin)

      database_id_field
      created_at_field
      updated_at_field

      def async_coupon
        Loaders::ActiveRecord.load(::Coupon, @object.coupon_id).then do |coupon|
          coupon
        end
      end


      field :expires_at, Scalars::DateTime, "The expiration date of the coupon", null: true
      field :code, String, null: true, description: "The coupon code describing the coupon"
      def code
        async_coupon.then do |coupon|
          coupon.code
        end
      end

      field :note, String, "A note describing the coupon", null: true
      def note
        async_coupon.then do |coupon|
          coupon.note
        end
      end

      field :discount, Float, "The amount the coupon takes off", null: true
      def discount
        async_coupon.then do |coupon|
          coupon.discount
        end
      end

      field :group, String, "The type of actor allowed to use coupon", null: true
      def group
        async_coupon.then do |coupon|
          coupon.group
        end
      end

    end
  end
end
