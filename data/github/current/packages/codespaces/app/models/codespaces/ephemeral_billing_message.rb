# typed: true
# frozen_string_literal: true

module Codespaces
  # Consider renaming to BillingMessage once our current BillingMessage is removed
  class EphemeralBillingMessage
    include ActiveModel::Model
    include GitHub::Memoizer
    validates :id, presence: true, length: { maximum: 36 }
    validates :codespace_plan_id, :codespace_guids, :caller_name, :created_at, presence: true
    validate :validate_billing_period
    validate :validate_tracked_usages
    validate :validate_location

    attr_reader :message_body, :vscs_target, :caller_name, :created_at, :codespace_plan_id

    def initialize(message_body:, vscs_target:, caller_name:, codespace_plan_id:)
      @message_body = message_body.deep_stringify_keys
      @vscs_target = vscs_target.to_s
      @caller_name = caller_name
      @codespace_plan_id = codespace_plan_id
      set_created_at
      set_tracked_usages
    end

    memoize def id
      message_body["id"]
    end

    # This can be removed once we remove BillingMessage. This is temporary to have parity with BillingMessage.
    def event_id
      id
    end

    memoize def environments
      message_body.dig("usageDetail", "environments")
    end

    def codespace_guids
      environments.map { |environment| environment["id"] }.uniq
    end

    memoize def period_start
      Time.parse(message_body.dig("periodStart"))
    end

    memoize def period_end
      Time.parse(message_body.dig("periodEnd"))
    end

    memoize def location
      message_body.dig("location")
    end

    def source_uri
      "gid://git-hub/Command/#{caller_name}/event_id/#{id}"
    end

    def tracked_usages_for(codespace_guid)
      @codespace_guid_to_tracked_usages_map[codespace_guid]
    end

    def is_prod_vscs_target?
      vscs_target.to_sym == :production
    end

    private

    def set_created_at
      @created_at ||= Time.now
    end

    def set_tracked_usages
      @codespace_guid_to_tracked_usages_map ||= Codespaces::BillingMessageTrackedUsage.generate_map(self)
    end

    def validate_billing_period
      unless period_start < period_end
        errors.add(:base, "start time must be before end time")
      end
    end

    def validate_location
      unless Codespaces::Locations::Region.find(location).present?
        errors.add(:base, "#{location} is not a valid location")
      end
    end

    def validate_tracked_usages
      tracked_usages = codespace_guids.map do |codespace_guid|
        tracked_usages_for(codespace_guid)
      end.flatten
      unless tracked_usages.all?(&:valid?)
        errors.add(:base, "Error mapping usage reports")
      end
    end
  end
end
