# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  # Parses response received from Microsoft SDN (Specially Designated Nationals)
  # EIS (Enterprise Information System) API
  class EisBusResponse

    class Request < T::Struct

      const :request_id, T.nilable(String), name: "ReqID"
      const :external_id, T.nilable(String), name: "ExternalRefID"
      const :result_text, T.nilable(String), name: "Result"
      const :status_reason, T.nilable(String), name: "ResultDesc"
      const :type, T.nilable(String), name: "Type"
      const :alert_id, T.nilable(String), name: "AlertID"

      sig { returns(String) }
      def status
        T.must(result_text).parameterize.underscore
      end
    end

    class Response < T::Struct
      prop :requests, T::Array[Request], name: "ScrResp", default: []
    end

    class Message < T::Struct
      include GitHub::Memoizer

      const :eid, T.nilable(String), name: "EId"
      const :request_date_string, T.nilable(String), name: "DT"
      const :result_text, T.nilable(String), name: "SummResult"
      prop :response, Response, name: "ScrResps"

      sig { returns(Time) }
      def request_date
        Time.iso8601(T.must(request_date_string))
      end

      sig { returns(T.nilable(String)) }
      def external_id
        requests.first&.external_id
      end

      sig { returns(String) }
      def status
        T.must(result_text).parameterize.underscore
      end

      sig { returns(String) }
      memoize def status_reason
        requests.map { |request| "#{request.status}: #{request.status_reason}" if request.status_reason.present? }.compact_blank.join(", ")
      end

      sig { returns(T::Array[Request]) }
      def requests
        response.requests
      end
    end

    sig { returns(T::Array[Message]) }
    attr_accessor :messages

    sig { returns(String) }
    attr_accessor :last_offset

    sig { params(messages: T::Array[Message], last_offset: String).void }
    def initialize(messages:, last_offset:)
      @messages = messages
      @last_offset = last_offset
    end

    sig { params(response: T::Hash[Symbol, T.untyped]).returns(EisBusResponse) }
    def self.parse(response:)
      if response[:messages].nil? || response[:lastOffset].blank?
        raise EisBusResponseParsingError.new("EIS response is missing required key.")
      end

      parsed_messages = response[:messages].map do |message|
        self.extract_info_from_message(message.symbolize_keys, response[:lastOffset])
      end.reject(&:nil?)
      EisBusResponse.new(messages: parsed_messages, last_offset: response[:lastOffset])
    end

    sig { params(message: T::Hash[Symbol, T.untyped], offset: String).returns(T.nilable(Message)) }
    def self.extract_info_from_message(message, offset)
      cohort = message.dig(:properties, :Cohort)
      if cohort != "GITHUB-SELFSERV"
        Failbot.report(EisBusResponseParsingError.new("Message received isn't related to GitHub SelfServ. message offset: #{message.dig(:messageOffset)} in offset batch: #{offset}"))
        return nil
      end
      payload = message.dig(:messageBody, :messagePayload)
      unless payload.present?
        raise EisBusResponseParsingError.new("EIS response is missing required key :messageBody or :messagePayload. Error parsing offset #{offset}")
      end

      payload = JSON.parse(payload)
      results = payload.dig("ScrRespEnv", "ScrResps", "ScrResp")
      unless results.present? && results.kind_of?(Array)
        raise EisBusResponseParsingError.new("EIS response is missing required key :ScrRespEnv, :ScrResps or :ScrResp. Error parsing offset #{offset}")
      end

      parsed_message = T.let(Message.from_hash(payload["ScrRespEnv"]), Message)
      return nil unless parsed_message.requests.any?

      parsed_message.requests.each do |request|
        GlobalInstrumenter.instrument("sdn_eis_bus.messages_received", {
          message: {
            request_id: request.request_id,
            external_user_id: request.external_id,
            result: request.result_text,
            result_description: request.status_reason,
            type: request.type,
            alert_id: request.alert_id,
            eid: parsed_message.eid,
            date: Google::Protobuf::Timestamp.new(seconds: parsed_message.request_date.to_i)
          },
          last_offset: offset,
        })
      end

      parsed_message
    end
  end
end
