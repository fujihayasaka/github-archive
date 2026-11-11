# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    # Usage: bin/seed coupons
    class Coupons < Seeds::Runner
      sig { returns(String) }
      def self.help
        <<~EOF
        Seed coupons for local development

        Seeding
        - Update Copilot Pro products to be couponable
        - Creates general sample coupons
        - Creates plan-restricted coupons for sample plans (business, business_plus, pro, emu_user)
        - Creates product-specific coupons for Copilot Pro billing products
        EOF
      end

      sig { params(options: T::Hash[Symbol, String]).void }
      def self.run(options = {})
        require_relative "../factory_bot_loader"
        new.run
      end

      sig { void }
      def run
        update_products
        create_sample_coupons
      end

      private

      sig { void }
      def create_sample_coupons
        # General coupons with different configurations
        create_coupon(code: "percentage", discount: 0.5)
        create_coupon(code: "fixed", discount: 10)
        create_coupon(code: "limited", limit: 1)
        create_coupon(code: "multi_use", limit: 100)
        create_coupon(code: "expired", expires_at: 1.day.ago)
        create_coupon(code: "never_expires", duration: Coupon::FOREVER_DURATION)

        # Plan coupons
        create_coupon(code: "business", discount: 0.5, plan: "business")
        create_coupon(code: "business_plus", discount: 0.5, plan: "business_plus")
        create_coupon(code: "pro_plan", discount: 0.5, plan: "pro")

        # Create coupons for each billing product
        product_uuids.each { |product| create_coupon_for_product(product) }
      end

      sig { void }
      def update_products
        product_uuids.each do |product|
          product.update!(couponable: true)
          puts "Updated product #{product.name} - #{product.billing_cycle} to be couponable"
        end
      end

      sig { returns(ActiveRecord::Relation) }
      def product_uuids
        # For now we only want to make GitHub Copilot Pro products couponable
        #   in the future they may be others
        Billing::ProductUUID.where("LOWER(name) LIKE LOWER(:prefix)", prefix: "GitHub Copilot Pro%")
      end

      sig { params(code: String, kwargs: T.untyped).returns(Coupon) }
      def create_coupon(code:, **kwargs)
        coupon = Coupon.find_by(code: code)
        if coupon
          puts "Found existing coupon with code: #{coupon.code}"
        else
          coupon = FactoryBot.create(:coupon, code: code, **kwargs)
          puts "Created coupon with code: #{coupon.code}"
        end

        coupon
      end

      sig { params(product: Billing::ProductUUID).returns(Coupon) }
      def create_coupon_for_product(product)
        code = "#{product.name.parameterize.underscore}_#{product.billing_cycle}"
        coupon = create_coupon(code: code)

        if coupon.product_target.nil?
          coupon.assign_product_target!(
            product_type: product.product_type,
            product_key: product.product_key,
          )
          coupon.save!

          # Manually save the product_target since autosave is false
          if product_target = coupon.product_target
            product_target.coupon_id = coupon.id
            product_target.save!
            puts "  - Added product target to coupon #{coupon.code}"
          end
        end

        coupon
      end
    end
  end
end
