# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaBaseClient
    sig do
      params(
        current_user: User,
        permanent_name: String,
        revision_name: T.nilable(String),
        url: String,
        token: String,
        service: String,
      ).void
    end
    def initialize(current_user, permanent_name, revision_name, url, token, service)
      @current_user = current_user
      @permanent_name = permanent_name
      @revision_name = revision_name
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
      returns(String)
    end
    def revision_for_metrics
      case @revision_name
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
        e: T.any(Exception, String),
        start_time: Float,
        meth: Symbol,
        endpoint: T.nilable(String),
      ).void
    end
    def report_error(e, start_time, meth, endpoint)
      elapsed = GitHub::Dogstats.duration(start_time, Time.now.to_f)
      GitHub.dogstats.distribution("aca.call.duration", elapsed, tags: [
        "aca.endpoint:#{endpoint}",
        "aca.method:#{meth}",
        "aca.service:#{@service}",
        "runtime.revision:#{revision_for_metrics}",
        "success:false"
      ])

      attrs = {
        "aca.endpoint": endpoint,
        "aca.method": meth,
        "aca.service": @service,
        "aca.url": @default_url,
        "gh.actor.id":  @current_user.id,
        "gh.actor.login": @current_user.display_login,
        "runtime.permanent_name": @permanent_name,
        "runtime.revision": @revision_name,
        duration_ms: elapsed,
      }

      Failbot.report(e, attrs)
      GitHub.logger.error("ACA API request failed: #{e}", attrs)
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
      GitHub.dogstats.distribution("aca.call.duration", elapsed, tags: [
        "aca.endpoint:#{endpoint}",
        "aca.method:#{meth}",
        "aca.service:#{@service}",
        "aca.status:#{response.status}",
        "runtime.revision:#{revision_for_metrics}",
        "success:true",
      ])

      attrs = {
        "aca.endpoint": endpoint,
        "aca.method": meth,
        "aca.service": @service,
        "aca.status": response.status,
        "aca.url": @default_url,
        "gh.actor.id":  @current_user.id,
        "gh.actor.login": @current_user.display_login,
        "runtime.permanent_name": @permanent_name,
        "runtime.revision": @revision_name,
        "x-azure-ref": response.headers["x-azure-ref"],
        duration_ms: elapsed,
      }
      GitHub.logger.info("ACA API call", attrs)
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
    rescue => e # rubocop:disable Lint/GenericRescue
      report_error(e, start || Time.now.to_f, meth, endpoint)
      AcaResponse.new(status: 500, call_succeeded: false, options: { message: "Internal server error" })
    end
  end
end
