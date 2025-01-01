# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module ExportControllerHelper
    extend T::Sig
    extend T::Helpers

    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper

    abstract!

    requires_ancestor { ApplicationController }

    ExportJobStatus = ::SecurityCenter::Export::JobStatus
    # Rate limiter
    DEFAULT_MAX_REQUESTS = T.let(10, Integer)
    DEFAULT_TTL = T.let(10.minutes.to_i, Integer)

    sig { void }
    def show_export
      return head(:bad_request) if params[:export_id].blank?
      return head(:bad_request) unless ::SecurityCenter::Export::TokenGenerator.token_is_sha_256?(params[:export_id])

      status = ExportJobStatus.find(params[:export_id])
      unless status
        return head(:not_found) if request.referrer.nil? # user hit our endpoint manually (not via export button)
        return redirect_download_error(RuntimeError.new("Failed to find export JobStatus"))
      end

      requested_at = Time.parse(status.requested_at)
      export_id = create_export_id(
        status.query,
        requested_at,
        status.start_date,
        status.end_date,
      )
      return redirect_download_error(ArgumentError.new("export_id mismatch"), query: status.query) unless export_id == params[:export_id]

      return redirect_download_error(RuntimeError.new("Export JobStatus is not finished"), query: status.query) unless status.finished?
      return redirect_download_error(RuntimeError.new("Export JobStatus is not successful: #{status.error_message}"), query: status.query) unless status.success?

      respond_to do |format|
        format.csv do
          storage_service = ::SecurityCenter::Export::BlobStorageService.get(scope)

          requested_date = requested_at.utc.strftime("%Y-%m-%dT%Hh%Mm%Ss")
          filename = "#{file_name_prefix}_%{suffix}.csv" % {
            suffix: [scope.display_login, requested_date].join("_"),
          }

          storage_service_response = storage_service.retrieve(export_id, feature_type, filename)
          return head(:not_found) if storage_service_response.nil?

          redirect_to storage_service_response.blob_url

          GitHub.dogstats.increment("security_center.export.show_access_type", tags: [
            "feature:#{feature_type}",
            "scope:#{scope.class.name&.downcase}",
            "access_type:#{request.referrer.nil? ? "email" : "page"}"
          ])

          event_payload = {
            query: status.query,
            filename:,
            requested_at: requested_at,
          }
          event_payload[:start_date] = status.start_date.to_s if status.start_date
          event_payload[:end_date] = status.end_date.to_s if status.end_date

          instrument_audit_log_event(event: export_event, event_payload: event_payload)
        end
      end
    rescue => e # rubocop:todo Lint/GenericRescue
      redirect_download_error(e, query: status&.query)
    end

    sig { void }
    def create_export
      if user_request_at_limit?
        GitHub.dogstats.increment("security_center.export.at_request_limit", tags: ["scope:#{scope.class.name&.downcase}", "feature:#{feature_type}"])
        log_warn(
          "#{feature_type.humanize} export hit the maximum number of allowed requests",
          "gh.security_center.feature_type": feature_type,
          "gh.security_center.search.query": query,
        )

        return render json: { error: "Too many requests have been made. Please try again later." }, status: 429
      end

      requested_at = Time.now
      export_id = create_export_id(query, requested_at)

      status = ExportJobStatus.find(export_id)
      if status.blank? || status.error?
        status = create_job_status(export_id:, requested_at:)

        queue_job(requested_at, export_id, status)
      end

      body = {
        downloadExportUrl: download_export_url(export_id),
        jobStatusUrl: job_status_path(status.id),
      }

      render json: body, status: 202
    rescue => e # rubocop:todo Lint/GenericRescue
      status&.destroy # This will cause the job to bail if it hasn't started yet
      Failbot.report(e)
      log_warn(
        "#{feature_type.humanize} export failed to process the export request (#create)",
        "gh.security_center.feature_type": feature_type,
        "gh.security_center.search.query": query,
        "gh.security_center.error": e
      )
      GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.name&.downcase}", "feature:#{feature_type}", "action:create"])

      render json: { error: "We couldn't process your request to export your data. Please try again later. If the problem persists, please contact support." }, status: 500
    end

    sig { returns(String) }
    def export_event
      # TODO: update for business level
      "org.security_center_export_#{feature_type}"
    end

    sig { abstract.returns(T.any(Organization, Business)) }
    def scope; end

    sig { abstract.returns(String) }
    def feature_type; end

    sig { abstract.returns(String) }
    def file_name_prefix; end

    sig { abstract.params(event: String, event_payload: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def instrument_audit_log_event(event:, event_payload: nil); end

    sig { abstract.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).void }
    def queue_job(requested_at, export_id, job_status); end

    sig { abstract.params(query: String, requested_at: Time, start_date_string: T.nilable(String), end_date_string: T.nilable(String)).returns(String) }
    def create_export_id(query, requested_at, start_date_string = nil, end_date_string = nil); end

    sig { abstract.params(export_id: String, requested_at: T.nilable(Time)).returns(ExportJobStatus) }
    def create_job_status(export_id:, requested_at:); end

    sig { abstract.params(export_id: String).returns(String) }
    def download_export_url(export_id); end

    sig { abstract.params(query: T.nilable(String)).returns(String) }
    def redirect_path(query); end

    sig { returns(String) }
    memoize def query
      params[:query]
    end

    sig { params(e: StandardError, query: T.nilable(String)).void }
    def redirect_download_error(e, query: nil)
      Failbot.report(e)
      log_warn(
        "#{feature_type.humanize} export failed to download the file to the user (#show)",
        "gh.security_center.feature_type": feature_type,
        "gh.security_center.search.query": query,
        "gh.security_center.error": e
      )
      GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.name&.downcase}", "feature:#{feature_type}", "action:show"])

      flash[:export_error] = "We couldn't download your report. Please try exporting your CSV again. If the problem persists, please contact support."
      redirect_back_or_to redirect_path(query)
    end

    sig { abstract.returns(T::Boolean) }
    def rate_limit_enabled?; end

    sig { abstract.returns(String) }
    def user_rate_limit_key; end

    sig { returns(T::Boolean) }
    def user_request_at_limit?
      return false unless rate_limit_enabled?

      options = {
        max_tries:,
        ttl:,
      }

      rate_limit_increment(user_rate_limit_key, options).at_limit?
    end

    sig { returns(Integer) }
    def max_tries
      scale_factor = GitHub.flipper[:security_center_export_max_user_requests_scale_factor].percentage_of_actors_value
      scale_factor == 0 ? DEFAULT_MAX_REQUESTS : (scale_factor * DEFAULT_MAX_REQUESTS).floor
    end

    sig { returns(Integer) }
    def ttl
      scale_factor = GitHub.flipper[:security_center_export_user_requests_ttl_scale_factor].percentage_of_actors_value
      scale_factor == 0 ? DEFAULT_TTL : (scale_factor * DEFAULT_TTL).floor
    end
  end
end
