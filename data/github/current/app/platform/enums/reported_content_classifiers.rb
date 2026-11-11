# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ReportedContentClassifiers < Platform::Enums::Base
      docs_category :meta
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

      value "LOW_QUALITY", "A low quality piece of content", value: "low-quality" do
        visibility :public, environments: [:dotcom]
      end
    end
  end
end
