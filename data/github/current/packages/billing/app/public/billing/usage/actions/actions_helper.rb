# typed: strict
# frozen_string_literal: true

module Billing::Usage::Actions
  module ActionsHelper
    extend T::Sig

    # Some Product Sku names are are different in Meuse and dotcom. This method transforms them to what dotcom expects
    # windows => WINDOWS
    # macos => MACOS
    # linux => UBUNTU
    sig { params(sku_name: String).returns(String) }
    def self.serialize_product_sku_name(sku_name)
      sku_name = sku_name.gsub(/linux/, "ubuntu") if sku_name.start_with?("linux")
      sku_name = sku_name.upcase if %w[ubuntu macos windows].include?(sku_name)
      sku_name
    end

    # Returns relevant runners with zeroed quantities
    # {
    #   "UBUNTU" => 0,
    #   "MACOS" => 0,
    #   "WINDOWS" => 0,
    #   "ubuntu_4_core" => 0,
    #   "ubuntu_8_core" => 0,
    #   "ubuntu_16_core" => 0,
    #   "ubuntu_32_core" => 0,
    #   "ubuntu_64_core" => 0,
    #   "windows_4_core" => 0,
    #   "windows_8_core" => 0,
    #   "windows_16_core" => 0,
    #   "windows_32_core" => 0,
    #   "windows_64_core" => 0,
    #   "total" => 0
    # }
    ZEROED_ACTIONS_USAGES = T.let(
      Billing::Actions::MEUSE_RUNNERS.map { |sku_name| [serialize_product_sku_name(sku_name), 0] }
        .to_h.with_indifferent_access.merge(total: 0).freeze,
      ActiveSupport::HashWithIndifferentAccess
    )

    protected

    sig { params(sku_name: String).returns(String) }
    def serialize_product_sku_name(sku_name)
      ActionsHelper.serialize_product_sku_name(sku_name)
    end

    # Transforms the usages into our formatted product_skus and effective quantities
    # {
    #   "UBUNTU" => linux_effective_quantity,
    #   "MACOS" => macos_effective_quantity,
    #   "WINDOWS" => windows_effective_quantity,
    #   "ubuntu_4_core" => linux_4_core_effective_quantity,
    #   "ubuntu_8_core" => linux_8_core_effective_quantity,
    #   "ubuntu_16_core" => linux_16_core_effective_quantity,
    #   "ubuntu_32_core" => linux_32_core_effective_quantity,
    #   "ubuntu_64_core" => linux_64_core_effective_quantity,
    #   "windows_4_core" => windows_4_core_effective_quantity,
    #   "windows_8_core" => windows_8_core_effective_quantity,
    #   "windows_16_core" => windows_16_core_effective_quantity,
    #   "windows_32_core" => windows_32_core_effective_quantity,
    #   "windows_64_core" => windows_64_core_effective_quantity,
    #   "total" => total_with_entitlements + total_without_entitlements
    # }
    sig do
      params(usages: T::Array[Billing::Usage::ProductUsage])
        .returns(ActiveSupport::HashWithIndifferentAccess)
    end
    def transformed_actions_usages(usages:)
      Billing::Actions::MEUSE_RUNNERS.map do |sku_name|
        quantity = usages.detect { |usage| usage.product_sku_name == sku_name }&.effective_quantity || 0
        [serialize_product_sku_name(sku_name), quantity]
      end.to_h.with_indifferent_access.merge(total: usages.sum(&:effective_quantity))
    end

    # Returns the formatted UI display name for a Meuse SKU name.
    sig { params(sku_name: String).returns(String) }
    def get_display_name(sku_name)
      sku_names = {
        linux: "Ubuntu 2-core",
        linux_16_core: "Ubuntu 16-core",
        linux_16_core_arm: "Ubuntu ARM 16-core",
        linux_2_core_advanced: "Ubuntu Advanced 2-Core",
        linux_2_core_arm: "Ubuntu ARM 2-core",
        linux_32_core: "Ubuntu 32-core",
        linux_32_core_arm: "Ubuntu ARM 32-core",
        linux_4_core: "Ubuntu 4-core",
        linux_4_core_arm: "Ubuntu ARM 4-core",
        linux_4_core_gpu: "Ubuntu GPU 4-core",
        linux_64_core: "Ubuntu 64-core",
        linux_64_core_arm: "Ubuntu ARM 64-core",
        linux_8_core: "Ubuntu 8-core",
        linux_8_core_arm: "Ubuntu ARM 8-core",
        macos: "macOS 3-core",
        macos_12_core: "macOS 12-core",
        macos_8_core: "macOS 8-core",
        macos_l: "macOS Large",
        macos_xl: "macOS XLarge",
        windows: "Windows 2-core",
        windows_16_core: "Windows 16-core",
        windows_16_core_arm: "Windows ARM 16-core",
        windows_2_core_advanced: "Windows Advanced 2-Core",
        windows_2_core_arm: "Windows ARM 2-core",
        windows_32_core: "Windows 32-core",
        windows_32_core_arm: "Windows ARM 32-core",
        windows_4_core: "Windows 4-core",
        windows_4_core_arm: "Windows ARM 4-core",
        windows_4_core_gpu: "Windows GPU 4-core",
        windows_64_core: "Windows 64-core",
        windows_64_core_arm: "Windows ARM 64-core",
        windows_8_core: "Windows 8-core",
        windows_8_core_arm: "Windows ARM 8-core",
      }

      sku_names[sku_name.to_sym] || sku_name.gsub("_", " ").titleize
    end

    # Returns the runtime type for the sku name
    sig { params(sku_name: String).returns(String) }
    def get_runtime_type(sku_name)
      if Billing::Actions::MEUSE_STANDARD_RUNNERS.include?(sku_name)
        "standard"
      else
        "custom"
      end
    end

    # Returns rate plan multiplier for the sku name. The multipliers are defined in the Meuse product_rate_plans table.
    # Since the get_usage_breakdown Meuse endpoint doesn't provide this information, we need to hardcode it here.
    sig { params(sku_name: String).returns(Integer) }
    def get_rate_plan_multiplier(sku_name)
      skus = {
        linux:  1,
        windows: 2,
        macos: 10,
        macos_12_core: 1,
        linux_4_core: 1,
        linux_8_core: 1,
        linux_16_core: 1,
        linux_32_core: 1,
        linux_64_core: 1,
        windows_4_core: 2,
        windows_8_core: 2,
        windows_16_core: 2,
        windows_32_core: 2,
        windows_64_core: 2,
      }
      skus[sku_name.to_sym] || 1
    end
  end
end
