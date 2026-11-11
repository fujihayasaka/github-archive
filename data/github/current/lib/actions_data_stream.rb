# typed: true
# frozen_string_literal: true

module ActionsDataStream
  autoload :EventForwarder, "actions_data_stream/event_forwarder"
  autoload :Twirp, "actions_data_stream/twirp"

  def self.load_from_global_id(global_id)
    raise NotImplementedError, "ActionsDataStream.load_from_global_id is not supported"
  end

  # Internal: Given an integer timestamp with milliseconds convert it to
  # a Time object with exact precision. The conversion needs special care
  # to ensure the full millisecond precision is preserved.
  #
  # Returns Time instance or nil if given nil.
  def self.milliseconds_to_time(timestamp)
    return timestamp if timestamp.nil? || timestamp.is_a?(Time)
    return unless (timestamp = timestamp.to_i).positive?

    case (Math.log10(timestamp).to_i + 1) # number of digits
    when 13 # Millisecond since the epoch
      seconds, milliseconds = timestamp.divmod(1e3)
      Time.at(seconds, milliseconds, :millisecond)
    when 10 # Seconds since the epoch, edge case
      Time.at(timestamp)
    end
  end

  # Internal: Given a Time-like object, convert to 13 digit integer timestamp
  # with millisecond precision
  #
  # Returns Integer or nil if given nil.
  def self.time_to_milliseconds(time)
    return time if time.nil? || time.is_a?(Integer)
    return nil if time.is_a?(String)
    (time.to_f * 1e3).to_i
  end

  # List of data stream actions. Similar to the Audit::ACTIONS array
  ACTIONS = [
    "workflow_run_execution.created",
    "actions.resolve_actions_request",
    "workflow_run_execution.completed",
  ]

end
