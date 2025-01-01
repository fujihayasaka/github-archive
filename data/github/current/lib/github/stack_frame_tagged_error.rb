# typed: true
# frozen_string_literal: true

class GitHub::StackFrameTaggedError < RuntimeError
  # Taken from the Rollbar gem
  FRAME_MATCH_REGEX = /(.*):\d+(?::in `([^']+)')?/
  # Scrub generated ERB method names
  ERB_SCRUB_REGEX = /_erb__[_\d]+\z/

  attr_reader :frame

  def initialize(message, frame)
    @message = message.to_s.freeze
    @frame = frame.to_s.freeze
    super("%s\nCalled from `%s`.\n" % [message, frame])
  end

  def tags
    @tags ||= [].tap do |frame_tags|
      match = frame.match(FRAME_MATCH_REGEX)
      next unless match

      filename, method = match[1], match[2]

      frame_tags.push("file:#{File.basename(filename)}")

      if method
        method = method.sub(ERB_SCRUB_REGEX, "_erb")
        frame_tags.push("method:#{method}")
      end
    end
  end
end
