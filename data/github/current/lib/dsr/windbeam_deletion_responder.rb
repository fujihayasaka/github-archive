# typed: true
# frozen_string_literal: true

module Dsr
  # Publishes a DataSubjectMessageResponse back to Windbeam via the
  # windbeam.v0.DataSubjectMessageResponseSecure Hydro topic.
  #
  # This is the participant response that tells Windbeam whether
  # the monolith successfully completed, skipped, or failed a
  # deletion stage.
  #
  # See: hydro-schemas/proto/hydro/schemas/windbeam/v0/data_subject_message_response.proto
  module WindbeamDeletionResponder
    extend self

    TOPIC = "windbeam.v0.DataSubjectMessageResponseSecure"
    SCHEMA = "hydro.schemas.windbeam.v0.DataSubjectMessageResponse"
    PARTICIPANT_NAME = "github"

    # Publish a response back to Windbeam indicating the result of processing
    # a DataSubjectMessage.
    #
    # message_id  - The message_id from the original DataSubjectMessage
    # request_id  - The request_id from the original DataSubjectMessage
    # response_type - One of :COMPLETE, :FAILED, :SKIPPED, :IN_PROGRESS
    # received_at - The Time when the original message was received
    def respond(message_id:, request_id:, response_type:, received_at:)
      GitHub.hydro_windbeam_publisher.publish(
        {
          response_id: SecureRandom.uuid,
          message_id: message_id,
          request_id: request_id,
          participant_name: PARTICIPANT_NAME,
          response_type: response_type,
          received_at: format_timestamp(received_at),
          responded_at: format_timestamp(Time.now.utc),
        },
        schema: SCHEMA,
        topic: TOPIC,
      )
    end

    private

    def format_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
    end
  end
end
