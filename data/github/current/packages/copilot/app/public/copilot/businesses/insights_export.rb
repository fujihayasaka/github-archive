# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module InsightsExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers

      abstract!

      # Generate export files for copilot insights usage data
      sig { params(business: ::Business).returns(T::Array[T::Hash[String, String]]) }
      def generate_export_files(business)
        unless GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          return development_sample_export_files
        end

        fetch_export_files_from_usage_service(business)
      end

      private

      sig { params(business: ::Business).returns(T::Array[T::Hash[String, String]]) }
      def fetch_export_files_from_usage_service(business)
        CopilotInsightsUsage::ReportDownloadService.fetch(
          path: "/enterprises/#{business.id}/copilot/metrics/reports/users-28-day/latest",
          entity_id: business.id,
          entity_type: "enterprise",
        )
      end

      sig { returns(T::Array[T::Hash[String, String]]) }
      def development_sample_export_files
        [
          { "name" => "testFile1.ndjson", "url" => "https://example.com/testFile.ndjson" },
          { "name" => "testFile2.ndjson", "url" => "https://example.com/testFile2.ndjson" },
        ]
      end
    end
  end
end
