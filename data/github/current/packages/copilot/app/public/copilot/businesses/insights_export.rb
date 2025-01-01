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
        if GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          usage_report = Copilot::Metrics::UsageReport.new(enterprise_id: business.id)

          latest_date = usage_report.get_latest_date

          if latest_date.nil?
            []
          else
            report_export = CopilotInsightsUsage::ReportExport.new(enterprise_id: business.id, date: latest_date)
            report_export.urls
          end
        else
          # In development, return sample file URLs
          [
            { "name" => "testFile1.json", "url" => "https://example.com/testFile.json" },
            { "name" => "testFile2.json", "url" => "https://example.com/testFile2.json" },
          ]
        end
      end

      # TODO: Add logic to generate export files for copilot insights code generation data
    end
  end
end
