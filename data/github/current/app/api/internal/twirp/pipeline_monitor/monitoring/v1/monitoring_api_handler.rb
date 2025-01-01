# typed: true
# frozen_string_literal: true

require "monolith-twirp-pipelinemonitor-monitoring"

module Api::Internal::Twirp::PipelineMonitor
  module Monitoring
    module V1
      class MonitoringAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::PipelineMonitor::Monitoring::V1::MonitoringAPIService
        allow_access_for :client, allowed_clients: ["pipeline_monitor"]
        exempt_from_tenant_context_requirement

        def send_hydro_message(req, env)
          if req.message.blank?
            return Twirp::Error.invalid_argument("missing message", argument: "message")
          end

          if req.schema.blank?
            return Twirp::Error.invalid_argument("missing topic", argument: "schema")
          end

          if req.topic.blank?
            return Twirp::Error.invalid_argument("missing topic", argument: "topic")
          end

          begin
            # Perform a decode/encode cycle to validate message
            klass = Hydro::Protobuf.get_schema_class(req.schema, Google::Protobuf::DescriptorPool.generated_pool)
          rescue Hydro::Error
            return Twirp::Error.invalid_argument("invalid schema", argument: "schema")
          end

          begin
            # Perform a decode/encode cycle to validate message
            decoded = klass.decode(req.message)
          rescue Google::Protobuf::ParseError
            return Twirp::Error.invalid_argument("invalid protobuf", argument: "message")
          end

          result = GitHub.hydro_publisher.publish(decoded.to_h, schema: req.schema, topic: req.topic)

          if result.success?
            { topic: req.topic }
          else
            Twirp::Error.internal("failed to publish hydro message", error: result.error)
          end
        end
      end
    end
  end
end
