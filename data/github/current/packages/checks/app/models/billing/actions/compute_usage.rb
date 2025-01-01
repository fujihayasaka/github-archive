# typed: true
# frozen_string_literal: true

module Billing::Actions
  class ComputeUsage
    include ActiveModel::Model
    include GitHub::Tracing
    include GitHub::Memoizer

    attr_accessor :job_id,
                  :actor_id,
                  :owner_id,
                  :owner,
                  :check_run_id,
                  :repository_id,
                  :repository,
                  :duration_in_milliseconds,
                  :job_runtime,
                  :start_time,
                  :end_time,
                  :runner_type,
                  :runner_properties,
                  :product_sku

    PRODUCTION_SKUS = Set[
      :linux,
      :windows,
      :macos,
      :macos_8_core,
      :macos_12_core,
      :macos_l,
      :macos_xl,
      :linux_2_core_advanced,
      :linux_4_core,
      :linux_8_core,
      :linux_16_core,
      :linux_32_core,
      :linux_64_core,
      :linux_4_core_gpu,
      :linux_2_core_arm,
      :linux_4_core_arm,
      :linux_8_core_arm,
      :linux_16_core_arm,
      :linux_32_core_arm,
      :linux_64_core_arm,
      :windows_2_core_advanced,
      :windows_4_core,
      :windows_8_core,
      :windows_16_core,
      :windows_32_core,
      :windows_64_core,
      :windows_4_core_gpu,
      :windows_2_core_arm,
      :windows_4_core_arm,
      :windows_8_core_arm,
      :windows_16_core_arm,
      :windows_32_core_arm,
      :windows_64_core_arm,
      :experimental,
    ].freeze

    MACOS_LATEST_XL         = "macos-latest-xl".freeze
    MACOS_12_XL             = "macos-12-xl".freeze
    MACOS_12_XL_BETA        = "macos-12-xl-beta".freeze
    MACOS_13_XL             = "macos-13-xl".freeze
    MACOS_LATEST_XL_ARM64   = "macos-latest-xl-arm64".freeze
    MACOS_13_XL_ARM64       = "macos-13-xl-arm64".freeze
    # newer large/xlarge labels:
    MACOS_12_LARGE          = "macos-12-large".freeze
    MACOS_13_LARGE          = "macos-13-large".freeze
    MACOS_LATEST_LARGE      = "macos-latest-large".freeze
    MACOS_13_XLARGE         = "macos-13-xlarge".freeze
    MACOS_14_LARGE          = "macos-14-large".freeze
    MACOS_14_XLARGE         = "macos-14-xlarge".freeze
    MACOS_15_LARGE          = "macos-15-large".freeze
    MACOS_15_XLARGE         = "macos-15-xlarge".freeze
    MACOS_LATEST_XLARGE     = "macos-latest-xlarge".freeze

    EXPERIMENTAL_SKUS = Set[
      "macos-13-arm64-experimental",
      "macos-12-xl-experimental"
    ].freeze

    trace_method :to_meuse
    trace_method :to_billing_platform

    def guid
      "Actions/#{job_id}"
    end

    def duration_in_minutes
      (duration_in_milliseconds / 1.minute.in_milliseconds.to_f).ceil
    end

    def to_meuse
      # Custom fields are used primarly only for reporting
      # While optional, if provided nil reports will be missing data when queried
      custom_fields = {}
      custom_fields["actions.check_run.id"] = check_run_id
      custom_fields["actions.workflow.id"] = workflow_id
      custom_fields["repository.id"] = repository_id

      {
        product_name: "actions",
        product_sku_name: product_sku_name,
        quantity: duration_in_minutes,
        account_id: owner_id,
        actor_id: actor_id,
        usage_at: end_time,
        usage_uuid: ::Billing::MeteredProduct.usage_uuid(guid),
        source_uri: source_uri,
        custom_fields: custom_fields,
      }
    end

    def to_billing_platform(sku_override = nil)
      {
        sku: sku_override || billing_platform_sku,
        quantity: duration_in_minutes,
        usage_at: end_time,
        source_uri: source_uri,
        entity: {
          customer_id: customer_for(billable_owner),
          organization_id: owner_id,
          repo_id: repository_id,
          actor_id: actor_id,
        },
      }
    end

    private

    def billing_platform_sku
      if sku = product_sku_name
        "actions_#{sku}"
      end
    end

    # Mapping to product SKU
    #
    # If Runner type is Self Hosted ignore
    # If Runner type is Hosted map Runtime -> Product SKU
    # If Runner type is Custom map Runtime & Properties -> Product SKU
    #
    # Returns the associated sku
    def product_sku_name
      runtime_sku = if job_runtime == :UBUNTU
        :linux
      else
        job_runtime.downcase
      end

      name = if runner_type == :RUNNER_TYPE_CUSTOM
        runner_product_sku
      elsif owner.feature_flag_enabled?(:actions_enable_macos_new_xlarge_large_rates, default: false)
        # these xl/xl_arm64 tests can be unified with large/xlarge once the feature flag is removed:
        if macos_xl_runner?
          :macos_l
        elsif macos_xl_arm64_runner?
          :macos_xl
        elsif macos_large_runner?
          :macos_l
        elsif macos_xlarge_runner?
          :macos_xl
        elsif experimental?
          :experimental
        elsif owner.feature_flag_enabled?(:actions_use_product_sku_from_hydro, default: true)
          if product_sku.nil? || product_sku.empty?
            runtime_sku.to_sym
          else
            product_sku.to_sym
          end
        else
          runtime_sku.to_sym
        end
      else
        if macos_xl_runner?
          :macos_12_core
        elsif macos_xl_arm64_runner?
          :macos_8_core
        elsif macos_large_runner?
          :macos_l
        elsif macos_xlarge_runner?
          :macos_xl
        elsif experimental?
          :experimental
        elsif owner.feature_flag_enabled?(:actions_use_product_sku_from_hydro, default: true)
          if product_sku.nil? || product_sku.empty?
            runtime_sku.to_sym
          else
            product_sku.to_sym
          end
        else
          runtime_sku.to_sym
        end
      end

      return nil unless PRODUCTION_SKUS.include?(name)

      name
    end

    def experimental?
      # https://github.com/github/c2c-actions-checks/issues/1421
      # This method checks if the job is running on an experimental runner, which are specifically used for testing purposes.
      # It is currently only enabled for specific runner labels listed in EXPERIMENTAL_SKUS and protected by two feature flags (one in dotcom, one in launch).
      # This is likely to be replaced in FY23Q4 by the checks team. Reach out to #actions-checks for questions on it.

      return false if runner_properties_json.blank?

      return false unless runner_properties_json["RequestedLabel"].present?

      # Check if RequestedLabel exists
      EXPERIMENTAL_SKUS.include?(runner_properties_json["RequestedLabel"].downcase)
    end

    def macos_xl_runner?

      # Check if job os is macos
      return false unless job_runtime == :MACOS

      return false if runner_properties_json.blank?

      return false unless runner_properties_json["RequestedLabel"].present?

      requested_label = runner_properties_json["RequestedLabel"].downcase

      # Check if RequestedLabel exists
      requested_label == MACOS_LATEST_XL ||
        requested_label == MACOS_12_XL ||
        requested_label == MACOS_12_XL_BETA ||
        requested_label == MACOS_13_XL
    end

    def macos_xl_arm64_runner?

      # Check if job os is macos
      return false unless job_runtime == :MACOS

      return false if runner_properties_json.blank?

      return false unless runner_properties_json["RequestedLabel"].present?

      requested_label = runner_properties_json["RequestedLabel"].downcase

      # Check if RequestedLabel exists
      requested_label == MACOS_LATEST_XL_ARM64 ||
        requested_label == MACOS_13_XL_ARM64
    end

    def macos_large_runner?

      # Check if job os is macos
      return false unless job_runtime == :MACOS

      return false if runner_properties_json.blank?

      return false unless runner_properties_json["RequestedLabel"].present?

      requested_label = runner_properties_json["RequestedLabel"].downcase

      # Check if RequestedLabel exists
      requested_label == MACOS_12_LARGE ||
        requested_label == MACOS_13_LARGE ||
        requested_label == MACOS_14_LARGE ||
        requested_label == MACOS_15_LARGE ||
        requested_label == MACOS_LATEST_LARGE
    end

    def macos_xlarge_runner?

      # Check if job os is macos
      return false unless job_runtime == :MACOS

      return false if runner_properties_json.blank?

      return false unless runner_properties_json["RequestedLabel"].present?

      requested_label = runner_properties_json["RequestedLabel"].downcase

      # Check if RequestedLabel exists
      requested_label == MACOS_13_XLARGE ||
      requested_label == MACOS_14_XLARGE ||
      requested_label == MACOS_15_XLARGE ||
        requested_label == MACOS_LATEST_XLARGE
    end

    def runner_product_sku
      if runner_properties_json.blank?
        return :unknown
      end

      product_sku_key = "ProductSku"
      if runner_properties_json.has_key?(product_sku_key)
        runner_properties_json[product_sku_key].downcase.to_sym
      else
        :unknown
      end
    end

    def workflow_id
      @workflow_id = Checks.domain.check_runs.for_id(check_run_id, repository_id: repository_id)&.check_suite&.workflow_run&.workflow_id
    end

    # source_uri utilizes a new instance of CheckRun to avoid sending an extra query to the database
    def source_uri
      @source_uri = CheckRun.new(id: check_run_id).to_global_id.to_s
    end

    def billable_owner
      @billable_owner ||= owner.try(:delegate_billing_to_business?) ? owner.business : owner
    end

    def customer_for(owner)
      if owner.delegate_billing_to_business?
        owner.business.customer_id
      else
        owner.customer&.id
      end
    end

    memoize def runner_properties_json
      return false unless runner_properties.present?
      begin
        JSON.parse(runner_properties)
      rescue ::JSON::ParserError
        false
      end
    end
  end
end
