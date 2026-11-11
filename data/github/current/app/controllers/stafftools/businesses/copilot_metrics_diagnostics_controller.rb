# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CopilotMetricsDiagnosticsController < Stafftools::Businesses::BusinessBaseController
      REPORT_TYPES = %w[enterprise-1-day users-1-day].freeze

      before_action :site_admin_only

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        only: [:show]

      def show
        min_date = 28.days.ago.to_date
        max_date = Date.yesterday
        selected_date = parse_selected_date(min_date, max_date)
        links_by_type = report_links(selected_date)

        render "stafftools/businesses/copilot_metrics_diagnostics/show", locals: {
          selected_date: selected_date,
          min_date: min_date,
          max_date: max_date,
          report_statuses: report_statuses(selected_date),
          report_links: links_by_type,
          live_etl_id: live_etl_id,
          membership_verification: verify_enterprise_membership,
        }
      end

      private

      def live_etl_id
        green_enabled = this_business.feature_flag_enabled?(:copilot_insights_usage_report_green_prefix, default: false)
        blue_override = this_business.feature_flag_enabled?(:copilot_insights_usage_report_blue_override, default: false)
        (green_enabled && !blue_override) ? "green" : "blue"
      end

      def parse_selected_date(min_date, max_date)
        date = begin
          Date.parse(params[:date])
        rescue ArgumentError, TypeError
          nil
        end

        return max_date if date.nil?

        date.clamp(min_date, max_date)
      end

      def report_statuses(selected_date)
        REPORT_TYPES.each_with_object({}) do |report_type, acc|
          acc[report_type] = CopilotInsightsUsage::ReportExistenceService.check(
            enterprise_id: this_business.id,
            report_type: report_type,
            day: selected_date,
          )
        end
      end

      def report_links(selected_date)
        REPORT_TYPES.each_with_object({}) do |report_type, acc|
          acc[report_type] = begin
            CopilotInsightsUsage::ReportDownloadService.fetch(
              path: "/enterprises/#{this_business.id}/copilot/metrics/reports/#{report_type}",
              entity_id: this_business.id,
              entity_type: "enterprise",
              query: { day: selected_date.to_s },
            )
          rescue => e
            GitHub.logger.error(
              "Failed to fetch Copilot Metrics report links",
              "code.namespace": self.class.name,
              "code.function": __method__.to_s,
              "gh.enterprise.id": this_business.id,
              "gh.copilot.report_type": report_type,
              "gh.requested_day": selected_date.to_s,
              "error.class": e.class.name,
              "error.message": e.message,
            )
            []
          end
        end
      end

      # Fetches the users report, extracts user IDs, and checks enterprise membership.
      # Returns a Hash with :status (:ok, :error, :no_report) and :non_members (Array of logins).
      def verify_enterprise_membership
        report_files = fetch_users_report_links
        return { status: :no_report, non_members: [] } if report_files.empty?

        user_ids = extract_user_ids_from_reports(report_files)
        return { status: :ok, non_members: [] } if user_ids.empty?

        non_member_logins = find_non_enterprise_members(user_ids)
        { status: :ok, non_members: non_member_logins }
      rescue => e
        GitHub.logger.error(
          "Failed to verify enterprise membership for metrics diagnostics",
          "code.namespace": self.class.name,
          "code.function": __method__.to_s,
          "gh.business.id": this_business.id,
          "exception.class": e.class.name,
          "exception.message": e.message,
        )
        { status: :error, non_members: [], error_message: e.message }
      end

      def fetch_users_report_links
        if GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          CopilotInsightsUsage::ReportDownloadService.fetch(
            path: "/enterprises/#{this_business.id}/copilot/metrics/reports/users-28-day/latest",
            entity_id: this_business.id,
            entity_type: "enterprise",
          )
        else
          []
        end
      end

      def extract_user_ids_from_reports(report_files)
        user_ids = Set.new

        report_files.each do |file|
          url = file["url"]
          next if url.blank?

          content = download_report_file(url)
          next if content.nil?

          content.each_line do |line|
            line = line.strip
            next if line.empty?

            parsed = GitHub::JSON.parse(line)
            user_id = parsed["github_com_user_id"]
            user_ids.add(user_id.to_i) if user_id.present?
          rescue JSON::ParserError
            next
          end
        end

        user_ids.to_a
      end

      def download_report_file(url)
        uri = T.cast(URI.parse(url), URI::HTTP)
        conn = GitHub::FaradayClient.external(
          "copilot_metrics_diagnostics",
          "#{uri.scheme}://#{uri.host}",
          request: {
            timeout: 30,
            open_timeout: 10,
          }
        )
        response = conn.get(uri.request_uri)
        return nil unless response.success?

        response.body
      rescue Faraday::Error => e
        GitHub.logger.warn(
          "Failed to download report file for metrics diagnostics",
          "code.namespace": self.class.name,
          "code.function": __method__.to_s,
          "gh.business.id": this_business.id,
          "exception.class": e.class.name,
          "exception.message": e.message,
        )
        nil
      end

      def find_non_enterprise_members(user_ids)
        users = ::User.where(id: user_ids).index_by(&:id)
        member_id_set = this_business.admin_and_organization_member_ids(actor_ids: user_ids).to_set
        non_member_ids = user_ids.reject { |id| member_id_set.include?(id) }
        non_member_ids.filter_map { |id| users[id]&.login }
      end
    end
  end
end
