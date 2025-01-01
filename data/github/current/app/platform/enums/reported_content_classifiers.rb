# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ReportedContentClassifiers < Platform::Enums::Base
      description "The reasons a piece of content can be reported or minimized."

      visibility :public

      value "SPAM", "A spammy piece of content", value: "spam" do
        visibility :public, environments: [:dotcom]
      end

      value "ABUSE", "An abusive or harassing piece of content", value: "abuse" do
        visibility :public, environments: [:dotcom]
      end

      value "OFF_TOPIC", "An irrelevant piece of content", value: "off-topic" do
        visibility :public
      end

      value "OUTDATED", "An outdated piece of content", value: "outdated" do
        visibility :public
      end

      value "DUPLICATE", "A duplicated piece of content", value: "duplicate" do
        visibility :public
      end

      value "RESOLVED", "The content has been resolved", value: "resolved" do
        visibility :public
      end
    end
  end
end
