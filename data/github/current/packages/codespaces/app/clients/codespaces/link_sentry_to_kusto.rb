# typed: true
# frozen_string_literal: true

# Links Sentry errors to Kusto by adding a link to the error context before the error is logged to Sentry
module Codespaces
  class LinkSentryToKusto < Faraday::Response::Middleware
    CLUSTER = "dataexplorer.azure.com"
    DATABASE_NAME = "CodespacesProd"
    CODESPACES_RESPONSE_ID_HEADERS = %w(vssaas-request-id x-ms-correlation-request-id x-ms-request-id)

    attr_reader :error_reporter

    QUERY_TEMPLATE = <<~QUERY
      let ['_databaseName']='CodespacesProd';
      // Remove above and uncomment to query other environments
      // let ['_databaseName']='CodespacesPpe';
      // let ['_databaseName']='CodespacesDev';
      database(_databaseName).table("RawEvent")
      // Uncomment to only show errors
      // | where level == "error"
      | where Properties has "%s"
      | extend ErrorException = tostring(Properties.ErrorException)
      | extend ErrorMessage = tostring(Properties.ErrorMessage)
      | extend ErrorDetail = tostring(Properties.ErrorDetail)
      | project ["time"], msg, ErrorDetail, ErrorException, ErrorMessage, Properties
      | order by ['time'] desc
    QUERY

    def initialize(app, error_reporter = ErrorReporter, options = {})
      super(app)
      @error_reporter = error_reporter
      yield error_reporter if block_given?
    end

    def call(env)
      super
    rescue StandardError => e # rubocop:todo Lint/RescueException
      on_error(e)
      raise
    end

    def on_complete(env)
      if request_id = request_id_from_headers(env.response_headers)
        error_reporter.push(kusto_request_url: kusto_url(request_id))
      end
    end

    def on_error(error)
      # The base Faraday::Error that we'd expect to be catching in #call above should have a `response` method on it.
      # We eventually catch these and wrap them in our own flavors but that takes place up in our Client layer.
      # https://github.com/lostisland/faraday/blob/v0.17.5/lib/faraday/error.rb
      return unless error.respond_to?(:response)

      response = error.response
      if response && request_id = request_id_from_headers(response[:headers])
        error_reporter.push(kusto_request_url: kusto_url(request_id))
      end
    end

    private

    def request_id_from_headers(headers)
      return unless headers.present?

      headers.transform_keys(&:downcase).values_at(*CODESPACES_RESPONSE_ID_HEADERS).compact.first
    end

    def kusto_url(request_id)
      # https://learn.microsoft.com/en-us/azure/data-explorer/kusto/api/rest/deeplink
      template = Addressable::Template.new("https://{cluster}/{database_name}{?query*}")
      query = QUERY_TEMPLATE % request_id
      zipped = ActiveSupport::Gzip.compress(query)
      encoded = Base64.encode64(zipped)
      query_params = { "query" => encoded }
      template.expand({
        "cluster" => CLUSTER,
        "database_name" => DATABASE_NAME,
        "query" => query_params
      }).to_s
    end
  end
end
