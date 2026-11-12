# frozen_string_literal: true

RSpec.describe BillingPlatform::Client do
  context "timeout configuration" do
    describe "default behavior (no timeouts set)" do
      it "does not set timeout or open_timeout on the Faraday connection" do
        client = described_class.new(hmac_key: "test-key")
        connection = client.customer_api.instance_variable_get(:@conn)

        expect(connection.options.timeout).to be_nil
        expect(connection.options.open_timeout).to be_nil
      end
    end

    describe "explicit timeout overrides" do
      it "applies custom timeout values" do
        client = described_class.new(hmac_key: "test-key", timeout: 5, open_timeout: 1)
        connection = client.customer_api.instance_variable_get(:@conn)

        expect(connection.options.timeout).to eq(5)
        expect(connection.options.open_timeout).to eq(1)
      end
    end

    describe "caller block still works" do
      it "yields the connection to the caller block" do
        block_called = false
        client = described_class.new(hmac_key: "test-key") do |conn|
          block_called = true
          conn.headers["X-Custom"] = "test"
        end
        connection = client.customer_api.instance_variable_get(:@conn)

        expect(block_called).to be true
        expect(connection.headers["X-Custom"]).to eq("test")
      end
    end

    describe "timeout with caller block" do
      it "applies timeouts alongside caller-provided middleware" do
        client = described_class.new(hmac_key: "test-key", timeout: 2, open_timeout: 0.5) do |conn|
          conn.headers["X-Custom"] = "test"
        end
        connection = client.customer_api.instance_variable_get(:@conn)

        expect(connection.options.timeout).to eq(2)
        expect(connection.options.open_timeout).to eq(0.5)
        expect(connection.headers["X-Custom"]).to eq("test")
      end
    end
  end
end
