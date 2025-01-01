# typed: true
# frozen_string_literal: true

# AuditLogSinkConfiguration is the base class for audit log sink
# models.
class AuditLogSinkConfiguration < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include Instrumentation::Model

  has_one :audit_log_stream_configuration, as: :sink

  after_commit :instrument_update, on: :update

  self.abstract_class = true

  def event_prefix
    :audit_log_streaming
  end

  def instrument_update
    instrument :update
  end

  # Check verifies if we can connect to the endpoint successfully.
  def check(business)
    client = GitHub.driftwood_client_v1
    res = check_query(client, business).execute
    res["ok"] ? "ok" : res["message"]
  end

  # Returns the sink URL for the given business that shows the sink's configuration page
  def sink_url(business, stream_id)
    UrlHelpers.public_send(sink_url_method(business), business, stream_id)
  end

  # Sink models need to implement this method to build a Twirp query to check
  # the endpoint.
  #
  # The method takes two arguments: a driftwood client and the sink business.
  def check_query(client, business)
    raise "Not implemented"
  end

  # Sink models need to implement this to return the method that is used
  # to build the sink URL that is used by the sink_url method.
  def sink_url_method(business = nil)
    raise "Not implemented"
  end

  # Sink models need to implement this method to return the string representation
  # of the sink type that will be showed to users.
  def sink_type
    raise "Not implemented"
  end

  # Sink models need to implement this method to return the string representation
  # of the sink details that will be showed to users.
  def sink_details
    raise "Not Implemented"
  end

  # Sink models need to implement this method to return an object that will be used
  # to respond to Twirp API calls in Api::Internal::Twirp::Auditlog::Streaming::V1::StreamingAPIHandler
  def as_streaming_api_conf
    raise "Not Implemented"
  end

  # Sink models need to implement this method to return the key that is used in the
  # Twirp API calls in Api::Internal::Twirp::Auditlog::Streaming::V1::StreamingAPIHandler responses
  def streaming_api_conf_key
    raise "Not Implemented"
  end

  def get_input
    raise NotImplementedError
  end

  # Check whether users accidentally included white spaces in their inputs
  def input_contains_whitespaces?
    input = get_input
    input.match?(/[\u200B-\u200D\uFEFF]/)
  end
end
