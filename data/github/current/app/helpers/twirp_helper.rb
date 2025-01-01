# typed: true
# frozen_string_literal: true

module TwirpHelper
  class TwirpError < StandardError
    attr_reader :msg
    def initialize(msg)
      @msg = msg
      super(msg)
    end
  end

  def self.rescue_from_twirp_errors(service_name, app: nil, expected_errors: [])
    raise ArgumentError, "A block must be passed to #{__method__}" unless block_given?
    begin
      resp = yield
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      self.failbot_report(e, app: app)
      return TwirpResponse.new(status: 503, call_succeeded: false)
    end

    if resp.nil?
      self.failbot_report(StandardError.new("Unexpected nil response from #{service_name}"), app: app)
      return TwirpResponse.new(status: 503, call_succeeded: false)
    end

    return TwirpResponse.new(status: 200, value: resp.data, call_succeeded: true) if resp.error.nil?

    case resp.error.code
    when :not_found
      TwirpResponse.new(status: 404, call_succeeded: false)
    when :failed_precondition
      TwirpResponse.new(status: 422, options: { message: "Bad request - #{resp.error.msg}" }, call_succeeded: false)
    when :already_exists
      self.report_twirp_error(resp.error, app: app) unless expected_errors.include?(:already_exists)
      TwirpResponse.new(status: 409, options: { message: "Already exists - #{resp.error.msg}" }, call_succeeded: false)
    when :deadline_exceeded
      self.report_twirp_error(resp.error, app: app)
      TwirpResponse.new(status: 500, call_succeeded: false)
    when :internal
      self.report_twirp_error(resp.error, app: app)
      TwirpResponse.new(status: 500, call_succeeded: false)
    when :unavailable
      self.report_twirp_error(resp.error, additional_info: "#{service_name} unavailable to serve requests", app: app)
      TwirpResponse.new(status: 503, options: { message: "#{service_name} service unavailable" }, call_succeeded: false)
    when :invalid_argument
      TwirpResponse.new(status: 422, options: { message: "Invalid Argument - #{resp.error.msg}" }, call_succeeded: false)
    when :permission_denied
      TwirpResponse.new(status: 403, options: { message: "Forbidden" }, call_succeeded: false)
    when :unauthenticated
      self.report_twirp_error(resp.error, app: app)
      TwirpResponse.new(status: 401, call_succeeded: false)
    when :resource_exhausted
      self.report_twirp_error(resp.error, app: app)
      TwirpResponse.new(status: 429, call_succeeded: false)
    when :out_of_range
      self.report_twirp_error(resp.error, app: app) unless expected_errors.include?(:out_of_range)
      TwirpResponse.new(status: 400, call_succeeded: false)
    else
      self.report_twirp_error(resp.error, app: app)
      TwirpResponse.new(status: 500, call_succeeded: false)
    end
  end

  def self.report_twirp_error(twerr, additional_info: "", app: nil)
    error_message = "[#{twerr.code}] #{twerr.msg}"
    unless additional_info.empty?
      error_message << " #{additional_info}"
    end
    error = TwirpHelper::TwirpError.new(error_message)

    self.failbot_report(error, app: app)
  end

  def self.failbot_report(error, app: nil)
    if app
      Failbot.report(error, { app: app })
    else
      Failbot.report(error)
    end
  end
end
