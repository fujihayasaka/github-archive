# typed: strict
# frozen_string_literal: true

module SecretScanning
  class AlertQueryService
    class CampaignCountsResponse
      CampaignCount = Struct.new(:campaign_id, :unresolved_count, :resolved_count, :dismissed_count, keyword_init: true) do
        sig { returns(Integer) }
        def open_count; unresolved_count; end

        sig { returns(Integer) }
        def closed_count; resolved_count; end

        sig { returns(Integer) }
        def open_with_links_count; 0; end

        sig { returns(Integer) }
        def autofix_supported_count; 0; end

        sig { returns(Integer) }
        def autofix_generated_count; 0; end

        sig { returns(Integer) }
        def autofix_accepted_count; 0; end

        sig { returns(Integer) }
        def total_count; open_count + closed_count; end
      end

      sig { returns(T::Array[CampaignCount]) }
      attr_reader :campaign_counts
      sig { params(campaign_counts: T::Array[CampaignCount]).void }
      def initialize(campaign_counts)
        @campaign_counts = campaign_counts
      end
      # Provide `.data` so callers can chain `.data.campaign_counts`
      sig { returns(SecretScanning::AlertQueryService::CampaignCountsResponse) }
      def data
        self
      end
    end
  end
end
