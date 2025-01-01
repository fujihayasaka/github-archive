# Best Effort: The order of message processing is not important, and processing of future messages
#  should continue, potentially at the expense of one lost message. If the message causes a downstream
#  error, we will NOT stop processing, but instead will skip the message. Some exceptions may
#  still cause the process to crash (like a NoMemoryError), but we will still attempt to mark these
#  messages as processed so a future process will avoid potential problems.
class Ingest::Processor::BestEffortMessageHandler
  def handle_message_and_errors(options, &block)
    block.call
  rescue Google::Protobuf::ParseError, ArgumentError => e
    # Lost messages still represent things we should look into, and at some point these
    # should instead be traveling to a dead letter queue. We log cases of lost messages as a metric
    # as well, to allow us to alert on this. It's expected that an alert triager will be digging into
    # Sentry / Splunk logs to try and identify the problem repos and address the code change manually.
    Instrument.increment("etl.decode_failure", topic: options[:subscribe_to])
    Instrument.increment("etl.lost_best_effort_message", topic: options[:subscribe_to])
    Failbot.report(e)
  # There was previously code here that was rescuing Kafka::ProcessingError, but it seems unlikely that
  # this should ever be useful after we already have a message and are only calling dependency-graph-api code.
  rescue StandardError, SystemStackError => e
    # For StandardError rescues, we assume something is wrong with the message but we explicitly DO NOT
    # raise the error, because the this can crash the client processing loop.
    # We also rescue SystemStackError, because we use a fair number of external libs in manifest parsing
    # and their implementation blowing up shouldn't blow us up too. This is at the cost of us potentially
    # suppressing our own SystemStackErrors, but this isn't a large concern relative to the savings.
    Instrument.increment("etl.lost_best_effort_message", topic: options[:subscribe_to])
    Failbot.report(e)
  end

  def react_to_crashing_message(exception, consumer, message)
    # A message that would crash us should be treated as potentially poisonous and we
    # will allow the crash to happen (assuming something is environmentally wrong),
    # but we will attempt to mark the message in case it bears some responsibility.
    consumer.mark_message_as_processed(message)
    consumer.commit_offsets(message)
    Failbot.report(exception)
  rescue StandardError => e
    # This case is specifically to stop our reaction from causing additional problems that
    # could obfuscate normal error propagation.
    # If this is happening we're probably going to see a stuck offset.
    Instrument.increment("etl.message_not_marked_processed")
  end
end
