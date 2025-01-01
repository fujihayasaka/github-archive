# typed: strict
# frozen_string_literal: true

module Billing
  module Actions
    class UsageLineItemWrapper < Billing::BaseUsageLineItemWrapper

      PRODUCT_SKU_NAME_TO_RUNTIME_ENV_MAP = T.let({
        "linux" => "UBUNTU",
        "linux_16_core" => "UBUNTU_16_CORE",
        "linux_16_core_arm" => "UBUNTU_16_CORE_ARM",
        "linux_2_core_advanced" => "UBUNTU_2_CORE_ADVANCED",
        "linux_2_core_arm" => "UBUNTU_2_CORE_ARM",
        "linux_32_core" => "UBUNTU_32_CORE",
        "linux_32_core_arm" => "UBUNTU_32_CORE_ARM",
        "linux_4_core" => "UBUNTU_4_CORE",
        "linux_4_core_arm" => "UBUNTU_4_CORE_ARM",
        "linux_4_core_gpu" => "UBUNTU_4_CORE_GPU",
        "linux_64_core" => "UBUNTU_64_CORE",
        "linux_64_core_arm" => "UBUNTU_64_CORE_ARM",
        "linux_8_core" => "UBUNTU_8_CORE",
        "linux_8_core_arm" => "UBUNTU_8_CORE_ARM",
        "macos" => "MACOS",
        "macos_12_core" => "MACOS_12_CORE",
        "macos_8_core" => "MACOS_8_CORE",
        "macos_l" => "MACOS_LARGE",
        "macos_xl" => "MACOS_XLARGE",
        "windows" => "WINDOWS",
        "windows_16_core" => "WINDOWS_16_CORE",
        "windows_16_core_arm" => "WINDOWS_16_CORE_ARM",
        "windows_2_core_arm" => "WINDOWS_2_CORE_ARM",
        "windows_2_core_advanced" => "WINDOWS_2_CORE_ADVANCED",
        "windows_32_core" => "WINDOWS_32_CORE",
        "windows_32_core_arm" => "WINDOWS_32_CORE_ARM",
        "windows_4_core" => "WINDOWS_4_CORE",
        "windows_4_core_arm" => "WINDOWS_4_CORE_ARM",
        "windows_4_core_gpu" => "WINDOWS_4_CORE_GPU",
        "windows_64_core" => "WINDOWS_64_CORE",
        "windows_64_core_arm" => "WINDOWS_64_CORE_ARM",
        "windows_8_core" => "WINDOWS_8_CORE",
        "windows_8_core_arm" => "WINDOWS_8_CORE_ARM",
      }, T::Hash[String, String])

      sig { returns(Time) }
      def end_time
        usage_line_item.usage_at.to_time.utc
      end

      sig { returns(Integer) }
      def workflow_id
        usage_line_item.custom_fields["actions.workflow.id"].to_i
      end

      sig { returns(Integer) }
      def check_run_id
        usage_line_item.custom_fields["actions.check_run.id"].to_i
      end

      sig { returns(CheckRun) }
      def check_run
        @check_run ||= T.let(begin
          run = Checks.domain.check_runs.unsafe_for_id(check_run_id)
          raise ActiveRecord::RecordNotFound unless run
          run
        end, T.nilable(CheckRun))
      end

      sig { returns(String) }
      def job_runtime_environment
        line_item_product_sku = usage_line_item.product_sku.name
        PRODUCT_SKU_NAME_TO_RUNTIME_ENV_MAP[line_item_product_sku] || "RUNTIME_UNKNOWN"
      end

      sig { returns(String) }
      def sku_diplay_name
        "Compute - #{job_runtime_environment}"
      end

      sig { returns(Billing::Types::NonMoneyNumeric) }
      def duration_in_minutes
        # at the time of writing, the quantity for actions is always in minutes
        usage_line_item.quantity
      end

      # The effective quantity refers to the base quantity * the multiplier
      sig { returns(Billing::Types::NonMoneyNumeric) }
      def effective_duration_in_minutes
        usage_line_item.effective_quantity
      end
    end
  end
end
