# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module ExportControllerHelper
    extend T::Helpers

    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper

    abstract!

    requires_ancestor { ApplicationController }

    class ExportUserFacingError < StandardError; end

    ExportJobStatus = ::SecurityCenter::Export::JobStatus
    # Rate limiter
    DEFAULT_MAX_REQUESTS = T.let(10, Integer)
    DEFAULT_TTL = T.let(10.minutes.to_i, Integer)
    DEFAULT_ERROR_MESSAGE = "We couldn't generate your report. Please try again later. If the problem persists, please contact support."

    sig { void }
    def show
      return head(:bad_request) if params[:export_id].blank?
      return head(:bad_request) unless ::SecurityCenter::Export::TokenGenerator.token_is_sha_256?(params[:export_id])

      status = ExportJobStatus.find(params[:export_id])

      # If referrer is present and comes from our pages, we assume the export button made the request.
      # We want to report the error in this case because the status is expected to be present.
      # Otherwise the user may have navigated to the page directly (such as from the email link),
      # and we don't want to report the error because the status may genuinely not be present anymore.
      from_sc_page = request.referrer.present? && request.referrer.include?(redirect_path(nil))
      return redirect_download_error(RuntimeError.new("Failed to find export JobStatus"), status:, report_error: from_sc_page) unless status

      # We don't include the query in these redirects to avoid leaking the query to the wrong user or applying it to the wrong scope
      correct_user = status.requester_id == current_user&.id
      return redirect_download_error(RuntimeError.new("Export requester does not match current user"), status:, report_error: false) unless correct_user
      correct_scope = status.scope_id == scope.id && status.scope_type.downcase == scope.class.name&.downcase
      return redirect_download_error(RuntimeError.new("Export scope does not match current scope"), status:, report_error: false) unless correct_scope

      requested_at = Time.parse(status.requested_at)
      export_id = create_export_id(
        status.query,
        requested_at,
        status.start_date,
        status.end_date,
      )

      # We include the query for convenience for the user so they don't lose their query if they are redirected while on the page.
      return redirect_download_error_with_query(ArgumentError.new("export_id mismatch"), query: status.query, status:, report_error: true) unless export_id == params[:export_id]
      return redirect_download_error_with_query(RuntimeError.new("Export JobStatus is not finished: #{status.state}"), query: status.query, status:, report_error: true) unless status.finished?
      return redirect_download_error_with_query(RuntimeError.new("Export JobStatus is not successful: #{status.error_message}"), query: status.query, status:, report_error: true) unless status.success?

      respond_to do |format|
        format.csv do
          storage_service = ::SecurityCenter::Export::BlobStorageService.get

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
    rescue => e # rubocop:todo Lint/RescueException
      query = status.query if correct_user && correct_scope
      redirect_download_error_with_query(e, query:, status:, report_error: true)
    end

    sig { void }
    def create
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

        job = queue_job(requested_at, export_id, status)
        unless job
          raise RuntimeError.new("Failed to create export job")
        end

        status.queued!
      end

      body = {
        downloadExportUrl: download_export_url(export_id),
        jobStatusUrl: job_status_path(status.id),
      }

      render json: body, status: 202
    rescue ExportUserFacingError => e
      render_create_error(e, status:, error_message: e.message)
    rescue => e # rubocop:todo Lint/RescueException
      render_create_error(e, status:)
    end

    sig { returns(String) }
    def export_event
      "#{scope.is_a?(Organization) ? "org" : "business"}.security_center_export_#{feature_type}"
    end

    sig { abstract.returns(T.any(Organization, Business)) }
    def scope; end

    sig { abstract.returns(String) }
    def feature_type; end

    sig { abstract.returns(String) }
    def file_name_prefix; end

    sig { abstract.params(event: String, event_payload: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def instrument_audit_log_event(event:, event_payload: nil); end

    sig { abstract.params(requested_at: Time, export_id: String, job_status: ExportJobStatus).returns(T.untyped) }
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
      params[:query] || ""
    end

    sig { params(e: StandardError, status: T.nilable(ExportJobStatus), report_error: T::Boolean).void }
    def redirect_download_error(e, status:, report_error:)
      redirect_download_error_with_query(e, query: nil, status:, report_error:)
    end

    sig { params(e: StandardError, query: T.nilable(String), status: T.nilable(ExportJobStatus), report_error: T::Boolean).void }
    def redirect_download_error_with_query(e, query:, status:, report_error:)
      attrs = {
        "gh.security_center.feature_type": feature_type, # Not using export naming scheme because it's the feature type of the current controller, not necessarily the one used to generate the export ID
        "gh.security_center.export.id": status&.id,
        "gh.security_center.export.query": status&.query,
        "gh.security_center.export.requester_id": status&.requester_id,
        "gh.security_center.export.requested_at": status&.requested_at,
        "gh.security_center.export.scope_id": status&.scope_id,
        "gh.security_center.export.scope_type": status&.scope_type,
        "gh.security_center.export.start_date": status&.start_date,
        "gh.security_center.export.end_date": status&.end_date,
      }

      if report_error
        Failbot.report(e, **attrs)
        GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.name&.downcase}", "feature:#{feature_type}", "action:show"])
      else
        log_warn(
          "#{feature_type.humanize} export failed to download the file to the user (#show)",
          "gh.security_center.error": e,
          **attrs,
        )
      end

      flash[:export_error] = "We couldn't download your report. Please try exporting your CSV again. If the problem persists, please contact support."
      redirect_back_or_to redirect_path(query)
    end

    sig { params(e: StandardError, status: T.nilable(ExportJobStatus), error_message: String).void }
    def render_create_error(e, status:, error_message: DEFAULT_ERROR_MESSAGE)
      status&.destroy # This will cause the job to bail if it hasn't started yet

      Failbot.report(e)
      log_warn(
        "#{feature_type.humanize} export failed to process the export request (#create)",
        "gh.security_center.feature_type": feature_type,
        "gh.security_center.search.query": query,
        "gh.security_center.error": e
      )
      GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.name&.downcase}", "feature:#{feature_type}", "action:create"])

      render json: { error: error_message }, status: 500
    end

    sig { abstract.returns(String) }
    def user_rate_limit_key; end

    sig { returns(T::Boolean) }
    def user_request_at_limit?
      options = {
        max_tries: DEFAULT_MAX_REQUESTS,
        ttl: DEFAULT_TTL,
      }

      rate_limit_increment(user_rate_limit_key, options).at_limit?
    end
  end
end
