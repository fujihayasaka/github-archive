# typed: true
# frozen_string_literal: true

class FundingPlatform::CommunityBridge
  def self.name
    "Community Bridge"
  end

  def self.url
    URI("https://funding.communitybridge.org/projects/")
  end

  def self.key
    :community_bridge
  end

  def self.template_placeholder
    "# Replace with a single #{name} project-name e.g., cloud-foundry"
  end
end
