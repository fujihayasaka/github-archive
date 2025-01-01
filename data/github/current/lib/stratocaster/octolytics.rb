# typed: true
# frozen_string_literal: true

module Stratocaster
  module Octolytics
    autoload :Attributes, "stratocaster/octolytics/attributes"
    autoload :EventBuilder, "stratocaster/octolytics/event_builder"
    autoload :StringLengthPolicy, "stratocaster/octolytics/string_length_policy"
    autoload :Utf8Transcoder, "stratocaster/octolytics/utf8_transcoder"
  end
end
