# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module InsightsExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers

      abstract!

      # Generate export files for copilot insights usage data
      sig { params(organization: ::Organization).returns(T::Array[T::Hash[String, String]]) }
      def generate_export_files(organization)
        unless GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          return development_sample_export_files
        end

        fetch_export_files_from_usage_service(organization)
      end

      private

      sig { params(organization: ::Organization).returns(T::Array[T::Hash[String, String]]) }
      def fetch_export_files_from_usage_service(organization)
        CopilotInsightsUsage::ReportDownloadService.fetch(
          path: "/organizations/#{organization.id}/copilot/metrics/reports/users-28-day/latest",
          entity_id: organization.id,
          entity_type: "organization",
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
