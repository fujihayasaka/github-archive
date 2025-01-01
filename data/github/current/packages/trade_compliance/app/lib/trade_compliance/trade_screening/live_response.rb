# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  # Parses response received from Microsoft SDN (Specially Designated Nationals)
  # Live Screening API
  class LiveResponse

    # A map to convert between the SDN external errors and the internal GitHub errors
    # this map will be reiterated upon once the errors have been fully received.
    SDN_ERROR_CODE_MAP = T.let({
      "Authorization Error": "SdnAuthorizationError",
      "Internal Screening Error": "SdnScreeningServerError",
      "DataValidationError": "SdnDataValidationError",
    }.freeze, T::Hash[String, String])

    sig { returns(String) }
    attr_accessor :eid, :external_uuid, :status
    sig { returns(T.nilable(String)) }
    attr_accessor :status_reason, :request_id
    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    attr_accessor :screening_errors
    sig { returns(T::Array[LiveResponse]) }
    attr_accessor :live_responses

    sig { params(eid: String, external_uuid: String, status: String, status_reason: T.nilable(String), request_id: T.nilable(String), screenings_errors: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def initialize(eid:, external_uuid:, status:, status_reason: "", request_id: "", screenings_errors: {})
      @eid = eid
      @external_uuid = external_uuid
      @status = T.let(status.parameterize.underscore, String)
      @status_reason = status_reason
      @request_id = request_id
      @live_responses = T.let([], T::Array[LiveResponse])
      @screening_errors = T.let([], T::Array[T::Hash[Symbol, String]])

      collect_errors(screenings_errors)
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def errors
      (live_responses.flat_map(&:screening_errors).compact_blank + screening_errors).uniq
    end

    sig { returns(String) }
    def status_reasons
      reason = "#{status}: #{status_reason}" if status_reason.present?
      live_responses.map { |r| "#{r.status}: #{r.status_reason}" if r.status_reason.present? }.append(reason).compact_blank.join(",")
    end

    sig { params(external_uuid: String, eid: String, status_reason: T.nilable(String)).returns(LiveResponse) }
    def self.create_retry_response(external_uuid:, eid: "", status_reason: "")
      LiveResponse.new(eid: eid, external_uuid: external_uuid, status: "retry", status_reason: status_reason)
    end

    # Parse a live API response and create a new LiveResponse for each screening response
    sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(LiveResponse) }
    def self.parse(response:)
      if missing_keys = missing_required_keys(response)
        raise LiveResponseParsingError.new("SDN LIVE response is missing required keys: #{missing_keys.join(", ")}")
      end

      # Fetch the required keys from the response
      eid = response[:ScrRespEnv][:EId]
      screening_responses = response[:ScrRespEnv][:ScrResps][:ScrResp]
      if screening_responses.empty?
        raise LiveResponseEmptyError.new("Expected ScrResp array to have at least one response. EID: #{eid}")
      end

      external_id = screening_responses.first[:ExternalRefID]
      screening_response = LiveResponse.new(eid: eid, external_uuid: external_id, status: response[:ScrRespEnv][:SummResult])

      # Create a live response for each screening response object
      screening_responses.map do |screening_result|
        screening_response.live_responses << LiveResponse.new(
          external_uuid: screening_result[:ExternalRefID],
          eid: eid,
          request_id: screening_result[:ReqID],
          status: screening_result[:Result],
          status_reason: screening_result[:ResultDesc],
          screenings_errors: screening_result[:Errs] || {}
        )
      end

      screening_response
    end

    # Checks if the response is missing any required keys
    sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(T.nilable(T::Array[String])) }
    def self.missing_required_keys(response)
      missing_keys = []
      return missing_keys << "ScrRespEnv" unless response.dig(:ScrRespEnv)
      missing_keys << "EId" unless response.dig(:ScrRespEnv, :EId)
      return missing_keys << "ScrResps" unless response.dig(:ScrRespEnv, :ScrResps)
      missing_keys << "ScrResp" unless response.dig(:ScrRespEnv, :ScrResps, :ScrResp)

      missing_keys.presence
    end

    private

    # Collects the errors from the screening response and validates the responses expected screening values
    sig { params(screenings_errors: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def collect_errors(screenings_errors)
      result_errors = screenings_errors[:Err].presence || []

      # Add to the errors array each error in the screening response
      @screening_errors = result_errors.map do |error|
        next unless error_code = error[:ErrCode].presence
        mapped_error = SDN_ERROR_CODE_MAP.fetch(error_code.to_sym, "SdnErrorUnknown")

        unless SDN_ERROR_CODE_MAP.values.include?(mapped_error)
          Failbot.report(LiveResponseParsingError.new("SDN received error code wasn't found in the error code map. received code: #{error[:ErrCode]}"))
        end
        { code: mapped_error, message: error[:ErrDesc] }
      end.compact

      # Verify that the required keys have expected values
      msg_prefix = "SDN LIVE response is invalid: "
      @screening_errors << { code: "SdnErrorUnknown", message: msg_prefix + "EId" } unless eid.present?
      @screening_errors << { code: "SdnErrorUnknown", message: msg_prefix + "Screening status: #{status}" } unless valid_status?
      @screening_errors << { code: "SdnErrorUnknown", message: msg_prefix + "External ref" } unless external_uuid.present?
    end

    sig { returns(T::Boolean) }
    def valid_status?
      AccountScreeningProfile::VALID_SDN_STATUSES.include?(status.to_sym)
    end
  end
end
