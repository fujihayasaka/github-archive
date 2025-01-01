# typed: true
# frozen_string_literal: true
class ApiGatewayService::ClassroomClient
  class ClassroomApiError < StandardError; end
  class ConnectionFailed < ClassroomApiError; end
  class RequestTimedout < ClassroomApiError; end

  def classrooms(headers: {}, params: {})
    get "classrooms", headers, params
  end

  def classroom(classroom_id, headers: {}, params: {})
    get "classrooms/#{classroom_id}", headers, params
  end

  def assignments(classroom_id, headers: {}, params: {})
    get "classrooms/#{classroom_id}/assignments", headers, params
  end

  def assignment(assignment_id, headers: {}, params: {})
    get "assignments/#{assignment_id}", headers, params
  end

  def accepted_assignments(assignment_id, headers: {}, params: {})
    get "assignments/#{assignment_id}/accepted_assignments", headers, params
  end

  def assignment_grades(assignment_id, headers: {}, params: {})
    get "assignments/#{assignment_id}/grades", headers, params
  end

  def conn
    @conn ||= GitHub::FaradayClient::Internal.new(url: "#{GitHub.classroom_api_service_url}/api", request: { timeout: 10 }) do |conn|
      conn.response :json
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.classroom_hmac_key, header: "Request-HMAC"
      conn.use GitHub::FaradayMiddleware::Resilient, name: "classroom_client", options: {
        instrumenter: GitHub,

        # Seconds after tripping circuit before allowing retry
        sleep_window_seconds: 5,

        # % of "marks" that must be failed to trip the circuit
        error_threshold_percentage: 25,

        # Number of seconds in the statistical window
        window_size_in_seconds: 60,

        # Size of buckets in statistical window
        bucket_size_in_seconds: 10,
      }
      conn.adapter Faraday.default_adapter
    end
  end

  private

  def get(url, headers, params)
    conn.get(url) do |req|
      req.params = params
      req.headers = headers
    end

  rescue Faraday::ConnectionFailed => e
    Failbot.report(e, tags: ["classroom_client"])
    raise ConnectionFailed, e.message
  rescue Faraday::TimeoutError => e
    Failbot.report(e, tags: ["classroom_client"])
    raise RequestTimedout, e.message
  rescue Faraday::Error => e
    Failbot.report(e, tags: ["classroom_client"])
    raise ClassroomApiError, e.message
  end
end
