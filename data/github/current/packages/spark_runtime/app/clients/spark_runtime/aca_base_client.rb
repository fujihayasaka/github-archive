# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaBaseClient
    sig { returns(T.nilable(String)) }
    attr_reader :default_url, :service

    sig do
      params(
        current_user: User,
        url: String,
        token: String,
        service: String,
      ).void
    end
    def initialize(current_user, url, token, service)
      @current_user = current_user
      @default_url = url
      @token = token
      @service = service
    end

    sig do
      params(
        url: T.nilable(String)
      ).returns(::Faraday::Connection)
    end
    def create_connection(url = nil)
      aca_connection = GitHub::FaradayClient::External.new(url: url || @default_url)
      aca_connection.headers["Authorization"] = "token #{@token}"
      aca_connection
    end

    sig do
      params(
        revision_name: T.nilable(String)
      ).returns(String)
    end
    def revision_for_metrics(revision_name = nil)
      case revision_name
      when "spark-preview"
        "spark-preview"
      when nil
        "production"
      else
        "custom"
      end
    end

    sig do
      params(
        meth: Symbol,
        endpoint: T.nilable(String),
      ).returns(T::Array[String])
    end
    def tags_for_datadog(meth, endpoint)
      [
        "aca.endpoint:#{endpoint}",
        "aca.method:#{meth}",
        "aca.service:#{@service}",
      ]
    end

    sig do
      params(
        revision_name: T.nilable(String)
      ).returns(T::Array[String])
    end
    def extra_tags_for_app_revisions(revision_name = nil)
      [
        "runtime.revision:#{revision_for_metrics(revision_name)}",
      ]
    end

    sig do
      params(
        meth: Symbol,
        endpoint: T.nilable(String),
        elapsed: T.any(Float, Numeric),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def attributes_for_telemetry(meth, endpoint, elapsed)
      {
        "aca.endpoint": endpoint,
        "aca.method": meth,
        "aca.service": @service,
        "aca.url": @default_url,
        "gh.actor.id":  @current_user.id,
        "gh.actor.login": @current_user.display_login,
        "duration_ms": elapsed,
      }
    end

    sig do
      params(
        runtime_app: Spark::RuntimeApp,
        revision_name: T.nilable(String),
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def extra_attributes_for_runtime_app(runtime_app, revision_name = nil)
      workbench = Spark::Workbench.find_by(runtime_app: runtime_app)
      {
        "runtime.permanent_name": runtime_app.permanent_name,
        "runtime.revision": revision_name,
        "global.workbench_id": workbench&.uuid_string,
      }
    end

    sig do
      params(
        e: T.any(Exception, String),
        start_time: Float,
        meth: Symbol,
        endpoint: T.nilable(String),
      ).void
    end
    def report_error(e, start_time, meth, endpoint)
      elapsed = GitHub::Dogstats.duration(start_time, Time.now.to_f)

      tags = tags_for_datadog(meth, endpoint)
      tags << "success:false"

      report_metric(elapsed, tags)

      attrs = attributes_for_telemetry(meth, endpoint, elapsed)
      attrs.merge!({
        "success": false,
        "error_message": e.to_s,
      })

      Failbot.report(e, attrs)
      GitHub.logger.error("ACA API request failed", attrs)

      payload = Workbench::TelemetryInstrumenter::Payload.from_api(
        restricted: false,
        current_user: @current_user,
        event_type: "spark.aca_call",
        request_id: GitHub.context[:request_id] || "",
        session_id: GitHub.context[:actor_session]&.to_s || "",
        spark_id: attrs[:"global.workbench_id"] || "",
        context: attrs,
        timestamp: Time.now,
      )
      GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)
    end

    sig do
      params(
        elapsed: T.any(Float, Numeric),
        tags: T::Array[String],
      ).void
    end
    def report_metric(elapsed, tags)
      # Stubbing out dogstats gets hairy in the tests, so extracted to stub neatly
      GitHub.dogstats.distribution("aca.call.duration", elapsed, tags:)
    end

    sig do
      params(
        response: AcaResponse,
        start_time: Float,
        meth: Symbol,
        endpoint: T.nilable(String),
      ).void
    end
    def report_aca_call(response, start_time, meth, endpoint)
      elapsed = GitHub::Dogstats.duration(start_time, Time.now.to_f)

      tags = tags_for_datadog(meth, endpoint)
      tags << "success:true"
      tags << "aca.status:#{response.status}"

      report_metric(elapsed, tags)

      attrs = attributes_for_telemetry(meth, endpoint, elapsed)
      attrs.merge!({
        "aca.status": response.status,
        "x-azure-ref": response.headers["x-azure-ref"],
        "x-ms-correlation-id": response.headers["x-ms-correlation-id"],
      })

      GitHub.logger.info("ACA API call", attrs)

      payload = Workbench::TelemetryInstrumenter::Payload.from_api(
        restricted: false,
        current_user: @current_user,
        event_type: "spark.aca_call",
        request_id: GitHub.context[:request_id] || "",
        session_id: GitHub.context[:actor_session]&.to_s || "",
        spark_id: attrs[:"global.workbench_id"] || "",
        context: attrs,
        timestamp: Time.now,
      )
      GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)
    end

    sig do
      params(
        meth: Symbol,
        endpoint: T.nilable(String),
        blk: T.proc.returns(::Faraday::Response)
      ).returns(AcaResponse)
    end
    def rescue_from_aca_errors(meth, endpoint = nil, &blk)
      start = Time.now.to_f
      begin
        resp = yield
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        report_error(e, start, meth, endpoint)
        return AcaResponse.new(status: 503, call_succeeded: false, options: { message: "Connection failure: #{e.message}" })
      end

      if resp.nil?
        report_error("Empty response from ACA", start, meth, endpoint)
        return AcaResponse.new(status: 503, call_succeeded: false, options: { message: "No response" })
      end

      aca_response = AcaResponse.new(status: resp.status,
        call_succeeded: true,
        headers: resp.headers,
        value: resp.body)

      report_aca_call(aca_response, start, meth, endpoint)
      aca_response
    rescue => e # rubocop:disable Lint/RescueException
      report_error(e, start || Time.now.to_f, meth, endpoint)
      AcaResponse.new(status: 500, call_succeeded: false, options: { message: "Internal server error" })
    end
  end
end
