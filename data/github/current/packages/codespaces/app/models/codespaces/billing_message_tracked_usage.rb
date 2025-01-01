# typed: true
# frozen_string_literal: true

module Codespaces
  class BillingMessageTrackedUsage
    include ActiveModel::Model
    include GitHub::Memoizer
    class MappingError < StandardError; end
    class UnrecognizedTypeError < StandardError; end

    COMPUTE_USAGE_TYPE = "compute"
    STORAGE_USAGE_TYPE = "storage"
    USAGE_TYPES = [COMPUTE_USAGE_TYPE, STORAGE_USAGE_TYPE]

    # The shape of the object this returns is: { <codespace guid>: [ <BillingMessageTrackedUsage>, <BillingMessageTrackedUsage>, ... ]}.
    # The number of usage report objects depends on how many different kinds of usages (per SKU and usage type) are sent in the original billing message
    def self.generate_map(billing_message)
      codespace_guid_to_tracked_usages_map = Hash.new { |h, k| h[k] = [] }
      billing_message.environments.each do |environment|
        USAGE_TYPES.each do |usage_type|
          usages = environment.dig("resourceUsage", usage_type) || []
          codespace_guid = environment["id"]
          codespace_guid_to_tracked_usages_map[codespace_guid] += usages.map do |usage_data|
            create_report(usage_data:, usage_type:, codespace_guid:)
          end
        end
      end
      codespace_guid_to_tracked_usages_map
    end

    def self.create_report(usage_data:, usage_type:, codespace_guid:)
      case usage_type
      when STORAGE_USAGE_TYPE
        Codespaces::StorageBillingMessageTrackedUsage.new(usage_data: usage_data, codespace_guid: codespace_guid, usage_type: usage_type)
      when COMPUTE_USAGE_TYPE
        Codespaces::BillingMessageTrackedUsage.new(usage_data: usage_data, codespace_guid: codespace_guid, usage_type: usage_type)
      else
        raise UnrecognizedTypeError, "Unrecognized usage type: #{usage_type}"
      end
    end

    validates_presence_of :billable_duration_in_seconds,
                          :sku_name,
                          :codespace_guid,
                          :usage_type,
                          :sku

    validates :sku_name, inclusion: Skus.valid_sku_names
    validates :usage_type, inclusion: USAGE_TYPES

    validates :billable_duration_in_seconds, numericality: {
        greater_than_or_equal_to: 0,
    }

    attr_reader :sku_name, :billable_duration_in_seconds, :usage_type, :codespace_guid
    def initialize(usage_data:, codespace_guid:, usage_type:)
      @sku_name = usage_data["sku"]
      @billable_duration_in_seconds = usage_data["usage"]
      @codespace_guid = codespace_guid
      @usage_type = usage_type
      post_intialize(usage_data:, codespace_guid:, usage_type:)
    end

    def post_intialize(usage_data:, codespace_guid:, usage_type:)
      # can be overridden by subclasses
    end

    def billable_duration_in_hours
      (@billable_duration_in_seconds / 3600.0).round(5)
    end

    memoize def formatted_sku_name
      @sku_name&.underscore.upcase
    end

    memoize def sku
      Codespaces::Skus.sku_by_name(sku_name)
    end

    def is_compute?
      usage_type == COMPUTE_USAGE_TYPE
    end

    def is_storage?
      usage_type == STORAGE_USAGE_TYPE
    end
  end
end
