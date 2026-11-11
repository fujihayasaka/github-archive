# frozen_string_literal: true

class Reference < ApplicationRecord
  URL_PATTERN = %r{\Ahttps?://\S+\z}
  GITHUB_PATTERN = %r{\Ahttps?://github\.com/}

  belongs_to :advisory, touch: true

  validates :url, presence: true, format: URL_PATTERN

  def self.github?(url)
    GITHUB_PATTERN.match?(url)
  end

  def to_param
    "#{advisory.ghsa_id}:#{index}"
  end

  def hydro_payload
    {
      url: url,
    }
  end

  def github?
    self.class.github?(url)
  end
end
