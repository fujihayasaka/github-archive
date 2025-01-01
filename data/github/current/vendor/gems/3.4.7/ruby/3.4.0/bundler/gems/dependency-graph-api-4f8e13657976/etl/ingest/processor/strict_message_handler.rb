# Strict: The order of message processing is important, we do not want to miss a message.
#  we consider a poison message to be something that needs to be addressed in its positional order before
#  moving on to other messages.
class Ingest::Processor::StrictMessageHandler
  def handle_message_and_errors(options, &block)
    # strict handlers don't do any specific handling for messages, allowing them to crash to guarantee
    # order safety.
    block.call
  end

  def react_to_crashing_message(exception, consumer, message)
    # strict handlers don't do anything special for crashing messages
    Failbot.report(exception)
  end
end
