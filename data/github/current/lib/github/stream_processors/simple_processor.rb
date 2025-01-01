# typed: true
# frozen_string_literal: true

class GitHub::StreamProcessors::SimpleProcessor < GitHub::StreamProcessors::BaseProcessor
  DEFAULT_GROUP_ID = "simple_processor"
  DEFAULT_SUBSCRIBE_TO = /(github|octochat)\..*\Z/

  def setup(**kwargs)
    options[:group_id] ||= DEFAULT_GROUP_ID
    options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
  end

  def process_message(message)
    if message.key == "pause"
      pause(reason: "pause message received")
    end
  end
end
