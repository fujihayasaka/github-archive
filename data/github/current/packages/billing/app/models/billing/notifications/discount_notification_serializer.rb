# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class DiscountNotificationSerializer < BaseThresholdNotificationSerializer
      include ::Api::Serializer::BillingDependency

      delegate :discount, to: :notification

      # Conversion rates from dollars to usage units
      # Based on the TypeScript DISCOUNT_TARGET_DATA_MAP
      DOLLAR_TO_UNIT_CONVERSIONS = {
        # Actions: $0.006 per minute, so 1 dollar = ~166.667 minutes
        "actions" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_linux" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_macos" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_windows" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_linux_arm" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_windows_arm" => { multiplier: 500.0 / 3, unit: "min" },
        "actions_linux_slim" => { multiplier: 500.0 / 3, unit: "min" },

        # Storage: $0.25 per GB, so 1 dollar = 4 GB
        "actions_storage" => { multiplier: 4, unit: "GB" },
        "packages_storage" => { multiplier: 4, unit: "GB" },
        "shared_storage" => { multiplier: 4, unit: "GB" },

        # Packages bandwidth: $0.50 per GB, so 1 dollar = 2 GB
        "packages_bandwidth" => { multiplier: 2, unit: "GB" },

        # Git LFS Storage: $0.07 per GB, so 1 dollar = ~14.29 GB
        "git_lfs_storage" => { multiplier: 14.29, unit: "GB" },

        # Git LFS Bandwidth: $0.0875 per GB, so 1 dollar = ~11.43 GB
        "git_lfs_bandwidth" => { multiplier: 11.43, unit: "GB" },

        # Custom Image Storage: $0.07 per GB, so 1 dollar ~= 14.29
        "actions_custom_image_storage" => { multiplier: 14.2857, unit: "GB" },
      }.freeze

      sig { override.returns(String) }
      def text
        conversion = DOLLAR_TO_UNIT_CONVERSIONS[discount.pricing_target_id]

        formatted_amount = if conversion && discount.target_amount.positive?
          target_units = discount.target_amount * conversion[:multiplier]
          case conversion[:unit]
          when "min"
            "#{format_number(target_units.round)} #{metered_service_name}"
          when "GB"
            "#{format_storage(target_units)} of #{metered_service_name}"
          else
            metered_service_name
          end
        else
          metered_service_name
        end

        "Your plan includes #{formatted_amount} per month at no extra cost. You have used #{threshold}% so far this billing cycle."
      end

      sig { returns(Integer) }
      def threshold
        discount.threshold_percentage
      end

      sig { override.returns(T.untyped) }
      def resource
        discount
      end

      sig { override.returns(String) }
      def resource_type
        "discount"
      end

      sig { override.returns(String) }
      def mail_subject
        owner = notification.owner
        account_name = "#{owner.name}"
        "You have used #{threshold}% of the #{metered_service_name} included"
      end

      sig { override.returns(String) }
      def mail_product_title
        product_name = case discount.pricing_target_id
        when /\Aactions/
          "GitHub Actions"
        when /\Apackages/
          "GitHub Packages"
        when /\Agit_lfs/
          "Git LFS"
        when /\Acodespaces/
          "GitHub Codespaces"
        when /\Acopilot/
          "GitHub Copilot"
        else
          pricing_info = Billing::Platform::Api::Client.new.get_pricing(sku: discount.pricing_target_id)
          if pricing_info.is_a?(Hash) && pricing_info.dig(:pricing, :friendlyName)
            friendly_name = pricing_info.dig(:pricing, :friendlyName)
            "GitHub #{friendly_name}"
          else
            "GitHub #{discount.pricing_target_id.to_s.humanize}"
          end
        end

        "#{product_name} Usage"
      end

      sig { override.returns(String) }
      def metered_service_name
        get_credit_description([{ id: discount.pricing_target_id }])
      end

      sig { override.returns(String) }
      def progress_bar_title
        "Discount"
      end

      sig { override.returns(String) }
      def progress_bar_details_text
        current_dollars = discount.current_amount
        target_dollars = discount.target_amount

        return super unless current_dollars && target_dollars

        # Check if we have a conversion rate for this pricing target
        conversion = DOLLAR_TO_UNIT_CONVERSIONS[discount.pricing_target_id]

        if conversion
          # Convert dollars to usage units
          current_units = current_dollars * conversion[:multiplier]
          target_units = target_dollars * conversion[:multiplier]

          case conversion[:unit]
          when "min"
            "#{format_number(current_units.round)} min used / #{format_number(target_units.round)} min included"
          when "GB"
            "#{format_storage(current_units)} used / #{format_storage(target_units)} included"
          when "hr"
            "#{format_number(current_units.round)} hr used / #{format_number(target_units.round)} hr included"
          else
            # Fallback to dollar amounts if unit is unknown
            super
          end
        else
          # For unknown products, show dollar amounts
          super
        end
      end

      sig { params(number: Numeric).returns(String) }
      def format_number(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      sig { params(gb: Numeric).returns(String) }
      def format_storage(gb)
        if gb >= 1000
          tb_value = gb / 1000.0
          if tb_value == tb_value.to_i
            "#{tb_value.to_i} TB"
          else
            "#{tb_value.round(2)} TB"
          end
        else
          if gb == gb.to_i
            "#{gb.to_i} GB"
          else
            "#{gb.round(2)} GB"
          end
        end
      end

      sig { override.returns(Symbol) }
      def variant
        return :danger if discount.fully_applied?

        :warning
      end

      sig { override.returns(String) }
      def usage_reset_date_text
        billable_owner = notification.billable_owner
        next_cycle = billable_owner.next_metered_billing_cycle_starts_at
        return "Your usage resets at the beginning of your next billing cycle" unless next_cycle

        days_left = (next_cycle.to_date - Date.current).to_i
        formatted_date = next_cycle.strftime("%B %d, %Y")

        if days_left == 0
          "Your usage will reset today (#{formatted_date})"
        elsif days_left == 1
          "Your usage will reset tomorrow #{formatted_date}"
        else
          "Your usage will reset in #{days_left} days on #{formatted_date}"
        end
      end

      sig { override.returns(String) }
      def mail_icon
        case discount.pricing_target_id
        when /\Aactions/, "actions_linux", "actions_macos", "actions_windows", "actions_linux_arm", "actions_windows_arm", "actions_linux_slim", "actions_storage"
          "actions.png"
        when /\Apackages/, "packages_bandwidth", "packages_storage"
          "packages.png"
        else
          "cogs.png"
        end
      end
    end
  end
end
