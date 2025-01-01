# typed: true
# frozen_string_literal: true

module LeadIngestion
  class RestApiClient
    extend T::Sig

    def initialize(api_client = LeadIngestion::HttpClient.new)
      @api_client = api_client
    end

    class << self
      delegate :put_lead, to: :new
    end

    sig { params(lead: Hash).returns(Response) }
    def put_lead(lead)
      payload = make_payload(lead)
      response = @api_client.request(
        method: :post,
        slug: "lead",
        body: payload
      )
      GitHub.dogstats.increment("lead_ingestion_client", tags: ["status:#{response.status}", "errored:false", "method:put_lead"])
      Response.new(response, payload: payload)
    rescue Faraday::Error => err
      response = Response.new(err.response, payload: T.must(payload), error: err)
      GitHub.dogstats.increment("lead_ingestion_client", tags: ["status:#{response.status}", "errored:true", "method:put_lead"])
      response
    end

    private

    sig { params(data: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def make_payload(data)
      # required data fields
      data[:originSystemName] = "GitHub"
      data[:sourceSystemName] = "GitHub"
      {
        batchRequestId: SecureRandom.uuid,
        input: [
          {
            requestItemId: SecureRandom.uuid,
            data: data
          }
        ]
      }
    end

    class Response
      extend T::Sig
      attr_reader :error, :payload

      sig do
        params(
          response: T.nilable(T.any(Faraday::Response, T::Hash[T.untyped, T.untyped])),
          payload: T::Hash[Symbol, T.untyped],
          error: T.nilable(Faraday::Error)
        ).void
      end
      def initialize(response, payload:, error: nil)
        @response = response
        @payload = payload
        @error = error
      end

      sig { returns(T::Boolean) }
      def error?
        error.present?
      end

      sig { returns(T.any(Integer, String)) }
      def status
        status_from_response =
          case @response
          when Faraday::Response
            @response.status
          when Hash
            @response[:status]
          end

        status_from_response || "unknown"
      end
    end
  end
end
