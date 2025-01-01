# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesLinkSentryToKustoTest < GitHub::TestCase
  class MockFailbot
    def push(payload = {})
      payloads << payload
      yield if block_given?
    end

    def payloads
      @payloads ||= []
    end
  end

  setup do
    @failbot = MockFailbot.new
    @reporter = Codespaces::ErrorReporter.new(reporter: @failbot)
    @request_id = SecureRandom.uuid
    @connection = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |f|
      f.use Codespaces::LinkSentryToKusto, @reporter
      f.adapter :test do |stubs|
        stubs.get("/success") { [200, { "VSSaas-Request-ID" => @request_id }, "hello"] }
        stubs.post("/failure") { [400, { "X-MS-Correlation-Request-ID" => @request_id }, "7"] }
      end
    end
  end

  test "adds a link to kusto when a request succeeds" do
    @connection.get("/success")
    assert_equal @failbot.payloads.count, 1
    assert @failbot.payloads.first[:kusto_request_url].starts_with?("https://dataexplorer.azure.com/CodespacesProd?query=")
    assert query_from_url(@failbot.payloads.first[:kusto_request_url]).include?(@request_id)
  end

  test "adds a link to kusto when there's an error" do
    @connection.post("/failure", "{}")
    assert_equal @failbot.payloads.count, 1
    assert @failbot.payloads.first[:kusto_request_url].starts_with?("https://dataexplorer.azure.com/CodespacesProd?query=")
    assert query_from_url(@failbot.payloads.first[:kusto_request_url]).include?(@request_id)
  end

  def query_from_url(url)
    parsed_url = Addressable::URI.parse(url)
    query = parsed_url.query_values["query"]
    decoded = Base64.decode64(query)
    ActiveSupport::Gzip.decompress(decoded)
  end
end
