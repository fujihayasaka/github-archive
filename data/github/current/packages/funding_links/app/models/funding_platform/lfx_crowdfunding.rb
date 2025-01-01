# typed: strict
# frozen_string_literal: true

class FundingPlatform::LfxCrowdfunding
  extend T::Sig

  sig { returns String }
  def self.name
    "LFX Crowdfunding"
  end

  sig { returns URI }
  def self.url
    URI("https://crowdfunding.lfx.linuxfoundation.org/projects/")
  end

  sig { returns Symbol }
  def self.key
    :lfx_crowdfunding
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with a single #{name} project-name e.g., cloud-foundry"
  end
end
