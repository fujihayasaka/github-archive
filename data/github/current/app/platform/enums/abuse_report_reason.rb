# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AbuseReportReason < Platform::Enums::Base

      description "The reason a piece of content can be reported for abuse."
      visibility :internal

      value "UNSPECIFIED", "A reason was not specified", value: "unspecified"
      value "ABUSE", "An abusive or harassing piece of content", value: "abuse"
      value "SPAM", "A spammy piece of content", value: "spam"
      value "OFF_TOPIC", "An irrelevant piece of content", value: "off_topic"
    end
  end
end
