# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BillingDiscounts < Seeds::Runner
      def self.help
        <<~HELP
        Create a variety of discounts against billing-platform for development and testing.

        This will create 12 discounts with various configurations:
          - Different discount types (Percentage, FixedAmount, RecurringFixedAmount)
          - Different funding sources (Education, SocialImpact, BillingCorrection, etc.)
          - Different targets (Enterprise, SKU, Product)
          - Different date ranges (current, future)

        Options:
          --customer_id=<id>  Create discounts for a specific customer (must be a Business)
                              Defaults to github-inc business if not provided.

        Prerequisites:
          - billing-platform must be running locally
          - Start it with: cd /workspaces/billing-platform && script/server

        Example:
          bin/seed billing_discounts
          bin/seed billing_discounts --customer_id=123
        HELP
      end

      def self.run(options = {})
        customer_id = find_customer_id(options)
        return if customer_id.nil?

        create_discounts(customer_id)
      end

      def self.find_customer_id(options)
        customer_id_arg = options[:customer_id]

        if customer_id_arg.nil?
          puts "🔍 Finding GitHub Inc business..."
          business = Business.find_by(slug: "github-inc")

          unless business
            puts "❌ GitHub Inc business not found"
            puts "   Expected to find a business with slug 'github-inc'"
            puts "   Make sure the database is set up and seeded properly"
            puts "   You can run: bin/seed billing_business"
            puts ""
            puts "   Alternatively, provide a customer_id option:"
            puts "   bin/seed billing_discounts --customer_id=<id>"
            return nil
          end

          puts "✅ Found GitHub Inc business: #{business.name} (ID: #{business.id})"

          customer = business.customer
          unless customer
            puts "❌ No customer found for GitHub Inc business"
            return nil
          end

          puts "✅ Using customer ID: #{customer.id}"
          customer.id.to_s
        else
          puts "🔍 Validating provided customer ID: #{customer_id_arg}"

          customer = Customer.find_by(id: customer_id_arg)

          unless customer
            puts "❌ Customer not found with ID: #{customer_id_arg}"
            puts "   Please provide a valid customer_id."
            return nil
          end

          puts "✅ Found customer with ID: #{customer.id}"

          billable_owner = customer.billable_owner

          unless billable_owner
            puts "❌ Customer has no billable owner"
            return nil
          end

          unless billable_owner.is_a?(Business)
            puts "❌ This seed only supports Business billable owners"
            puts "   Found billable owner type: #{billable_owner.class.name}"
            puts "   Billable owner: #{billable_owner.respond_to?(:login) ? billable_owner.login : billable_owner.id}"
            puts ""
            puts "   This seed is designed for enterprise/business discounts only."
            puts "   Individual user or organization discounts are not supported."
            return nil
          end

          puts "✅ Validated billable owner is a Business: #{billable_owner.name} (slug: #{billable_owner.slug})"
          customer.id.to_s
        end
      end

      def self.create_discounts(customer_id)
        client = Billing::Platform::Api::Client.new

        # Define date helpers
        now = Time.now.utc
        today = now.to_i
        tomorrow = (now + 1.day).to_i
        one_week_from_now = (now + 7.days).to_i
        one_month_from_now = (now + 30.days).to_i
        two_months_from_now = (now + 60.days).to_i
        three_months_from_now = (now + 90.days).to_i
        six_months_from_now = (now + 180.days).to_i
        one_year_from_now = (now + 365.days).to_i

        discounts_config = [
          # 1. Enterprise-wide percentage discount (Education) - Starts today
          {
            name: "Enterprise Education 10% Discount",
            discount: {
              customerId: customer_id,
              targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
              percentage: 10.0,
              targetAmount: 0,
              startDate: today,
              endDate: six_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::Percentage,
              fundingSource: BillingPlatform::Api::V1::FundingSource::Education,
            }
          },

          # 2. Enterprise wide fixed amount discount (Social Impact) - Starts today
          {
            name: "Enterprise Social Impact $500 Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
              percentage: 0,
              targetAmount: 500, # $500
              startDate: today,
              endDate: three_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::FixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::SocialImpact,
            }
          },

          # 3. Enterprise recurring discount (GitHub for Startups) - Starts today
          {
            name: "Enterprise Startups Monthly $100 Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
              percentage: 0,
              targetAmount: 100, # $100 per month
              startDate: today,
              endDate: one_year_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::GitHubForStartups,
            }
          },

          # 4. SKU-specific percentage discount for Actions (Billing Correction) - Starts today
          {
            name: "Actions Linux 15% Discount",
            discount: {
              customerId: customer_id,
              targets: [{ id: "actions_linux", type: "SkuDiscount" }],
              percentage: 15.0,
              targetAmount: 0,
              startDate: today,
              endDate: three_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::Percentage,
              fundingSource: BillingPlatform::Api::V1::FundingSource::BillingCorrection,
            }
          },

          # 5. SKU-specific fixed amount for Codespaces (Open Source)
          {
            name: "Codespaces Open Source $200 Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: "codespaces_linux", type: "SkuDiscount" }],
              percentage: 0,
              targetAmount: 200, # $200
              startDate: today,
              endDate: six_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::FixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::OpenSource,
            }
          },

          # 6. Product-level percentage discount for Copilot (Sales Offer) - Starts tomorrow
          {
            name: "Copilot 20% Sales Offer",
            discount: {
              customerId: customer_id,
              targets: [{ id: "copilot", type: "ProductDiscount" }],
              percentage: 20.0,
              targetAmount: 0,
              startDate: tomorrow,
              endDate: one_year_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::Percentage,
              fundingSource: BillingPlatform::Api::V1::FundingSource::SalesOffer,
            }
          },

          # 7. Product-level recurring credit for Actions (Billing Correction) - Future start
          {
            name: "Actions Future Monthly $50 Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: "actions", type: "ProductDiscount" }],
              percentage: 0,
              targetAmount: 50, # $50 per month
              startDate: one_month_from_now,
              endDate: one_year_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::BillingCorrection,
            }
          },

          # 8. Multi-SKU percentage discount (Education) - Starts next week
          {
            name: "Multi-SKU Actions 25% Education Discount",
            discount: {
              customerId: customer_id,
              targets: [
                { id: "actions_linux", type: "SkuDiscount" },
                { id: "actions_windows", type: "SkuDiscount" },
                { id: "actions_macos", type: "SkuDiscount" }
              ],
              percentage: 25.0,
              targetAmount: 0,
              startDate: one_week_from_now,
              endDate: six_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::Percentage,
              fundingSource: BillingPlatform::Api::V1::FundingSource::Education,
            }
          },

          # 9. Expiring soon discount (Billing Correction) - Starts today, expires in 7 days
          {
            name: "Expiring Actions Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
              percentage: 0,
              targetAmount: 150, # $150
              startDate: today,
              endDate: one_week_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::FixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::BillingCorrection,
            }
          },

          # 10. Large enterprise percentage discount (Sales Offer) - Starts in 2 months
          {
            name: "Enterprise Premium 30% Discount",
            discount: {
              customerId: customer_id,
              targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
              percentage: 30.0,
              targetAmount: 0,
              startDate: two_months_from_now,
              endDate: one_year_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::Percentage,
              fundingSource: BillingPlatform::Api::V1::FundingSource::SalesOffer,
            }
          },

          # 11. SKU recurring for Packages (Open Source)
          {
            name: "Packages Monthly $75 Open Source Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: "packages_data_transfer", type: "SkuDiscount" }],
              percentage: 0,
              targetAmount: 75, # $75 per month
              startDate: today,
              endDate: six_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::RecurringFixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::OpenSource,
            }
          },

          # 12. Product fixed amount for Git LFS (Social Impact) - Starts today
          {
            name: "Git LFS Social Impact $300 Credit",
            discount: {
              customerId: customer_id,
              targets: [{ id: "git_lfs", type: "ProductDiscount" }],
              percentage: 0,
              targetAmount: 300, # $300
              startDate: today,
              endDate: three_months_from_now,
              discountType: BillingPlatform::Api::V1::DiscountType::FixedAmount,
              fundingSource: BillingPlatform::Api::V1::FundingSource::SocialImpact,
            }
          },
        ]

        puts ""
        puts "🚀 Creating #{discounts_config.size} discounts in billing-platform..."
        puts ""

        created_count = 0
        failed_count = 0

        discounts_config.each_with_index do |config, index|
          puts "#{index + 1}. Creating: #{config[:name]}"

          begin
            response = client.create_discount(discount: config[:discount])

            if response.is_a?(Billing::Platform::Api::Error)
              puts "   ❌ Failed: #{response.message}"
              failed_count += 1
            elsif response.is_a?(Hash) && response[:error]
              puts "   ❌ Failed: #{response[:error]}"
              failed_count += 1
            else
              puts "   ✅ Created successfully"
              created_count += 1
            end
          rescue StandardError => e
            puts "   ❌ Error: #{e.message}"
            failed_count += 1
          end
        end

        puts ""
        puts "=" * 50
        puts "📊 Summary:"
        puts "   ✅ Created: #{created_count}"
        puts "   ❌ Failed: #{failed_count}"
        puts "   📋 Total: #{discounts_config.size}"
        puts ""

        if failed_count > 0
          puts "⚠️  Some discounts failed to create."
          puts "   Make sure billing-platform is running locally."
          puts "   You can start it with: cd /workspaces/billing-platform && script/server"
        else
          puts "🎉 All discounts created successfully!"
        end

        puts ""
        puts "💡 Tips:"
        puts "   - View discounts in stafftools: /stafftools/enterprises/github-inc/billing/discounts"
        puts "   - Query discounts via API: client.get_all_discounts(customer_id: '#{customer_id}')"
      end
    end
  end
end
