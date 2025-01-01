# typed: strict
# frozen_string_literal: true

class FundingPlatform::Custom
  extend T::Sig

  sig { returns String }
  def self.name
    "Custom"
  end

  sig { returns T.nilable(URI) }
  def self.url
    nil
  end

  sig { returns Symbol }
  def self.key
    :custom
  end

  sig { returns String }
  def self.template_placeholder
    "# Replace with up to 4 custom sponsorship URLs e.g., ['link1', 'link2']"
  end
end
