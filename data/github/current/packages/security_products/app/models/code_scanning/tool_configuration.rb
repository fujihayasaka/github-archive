# typed: true
# frozen_string_literal: true

module CodeScanning
  # ToolConfiguration represents a configuration for a tool as shown on the tool
  # status page. It provides easy access to the fields required, and methods for
  # populating them from data from Turboscan.
  #
  # Configurations are called 'categories` in the Protobuf (`CategoryStatus` messages).
  # The term 'configuration' is the closest thing we have to a canonical term for this concept.
  class ToolConfiguration
    include GitHub::Memoizer
    class << self
      include CodeScanning::ToolStatusHelper
    end

    attr_reader :overall_status, :category

    sig do
      params(
        category: Turboscan::Proto::CategoryStatus,
        # overall_status will be one of the CodeScanning::Status::* constants, but we can't enforce that
        overall_status: Integer,
      ).void
    end
    def initialize(category:, overall_status:)
      @category = category
      @overall_status = overall_status
    end

    def first_scan
      @category.created_at&.to_time
    end

    def last_scan
      @category.updated_at&.to_time
    end

    def analysis_id
      @category.analysis_id
    end

    memoize def label
      self.class.format_category(@category.category)
    end

    sig do
      params(
        category: ::Turboscan::Proto::CategoryStatus,
      ).returns(String)
    end
    def self.slug(category:)
      GitHub::Hex.load(category.configuration_hash)
    end

    memoize def group_slug
      configuration_group = @category.configuration_group

      if configuration_group.present?
        ::CodeScanning::ToolConfigurationGroup.slug(configuration_group: configuration_group)
      end
    end

    def slug
      self.class.slug(category: @category)
    end
  end
end
