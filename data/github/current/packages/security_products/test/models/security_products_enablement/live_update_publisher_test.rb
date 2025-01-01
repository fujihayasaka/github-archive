# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class LiveUpdatePublisherTest < GitHub::TestCase
    include SecurityProductsEnablement::EnterpriseTestHelpers
    include HydroTestHelpers

    fixtures do
      @org = create(:organization)
    end

    setup do
      GitHub::WebSocket.enabled = true

      @publisher = SecurityProductsEnablement::LiveUpdatePublisher.new(@org)
    end

    teardown do
      GitHub::WebSocket.enabled = false
    end

    def channel(org)
      GitHub::WebSocket::Channels.security_configurations_update(org)
    end

    context "#repository_status" do
      test "raises on unsupported statuses" do
        assert_raises(ArgumentError) do
          @publisher.repository_status(repository_id: 1, config_name: "irrelevant", status: "unsupported")
        end
      end

      test "publishes to Alive" do
        @publisher.repository_status(repository_id: 1, config_id: 2, status: "attaching")

        expected = {
          type: "repository_statuses",
          repositoryStatuses: {
            1 => { status: "attaching", failure_reason: nil, configuration_id: 2 }
          }
        }.to_json

        assert_hydro_published(
          { channel: channel(@org), data: expected },
          schema: "live_updates.v0.Message",
          ignore_extra_keys: true
        )
      end

      test "publishes to Alive with just a status" do
        @publisher.repository_status(repository_id: 1, status: "attached")

        expected = {
          type: "repository_statuses",
          repositoryStatuses: {
            1 => { status: "attached", failure_reason: nil }
          }
        }.to_json

        assert_hydro_published(
          { channel: channel(@org), data: expected },
          schema: "live_updates.v0.Message",
          ignore_extra_keys: true
        )
      end
    end

    test "#configuration_updates" do
      security_configuration = create(:security_configuration, target: @org)
      @publisher.configuration_updates

      serializer = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org)
      serialized_configuration = serializer.serialize(security_configuration)

      expected = { type: "configuration_updates" }.to_json

      assert_hydro_published(
        { channel: channel(@org), data: expected },
        schema: "live_updates.v0.Message",
        ignore_extra_keys: true
      )
    end
  end
end
