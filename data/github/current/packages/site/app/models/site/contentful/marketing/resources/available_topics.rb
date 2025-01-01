# typed: true
# frozen_string_literal: true

module Site::Contentful::Marketing::Resources::AvailableTopics
  AVAILABLE_TOPICS = {
    "ai" => "AI",
    "devops" => "DevOps",
    "security" => "Security",
    "software-development" => "Software Development",
    "test-internal-only" => "Test Internal Only"
  }.freeze

  ALL_TOPICS = "All Topics"

  def self.available_public_topics
    AVAILABLE_TOPICS.keys - ["test-internal-only"]
  end
end
