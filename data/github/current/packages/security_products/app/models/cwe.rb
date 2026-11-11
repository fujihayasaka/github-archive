# typed: true
# frozen_string_literal: true

class CWE < ApplicationRecord::Notify
  CWE_PATTERN = /\ACWE-(\d{1,5})\z/
  attribute :name, StringFromBinary.new
  attribute :description, StringFromBinary.new

  scope :with_content_like, lambda { |query|
    with_substring("CONVERT(name USING utf8mb4)", query).or(with_substring("cwe_id", query))
  }

  validates :cwe_id, format: { with: CWE_PATTERN, allow_blank: false }
  validates :name, :description, presence: true

  def reset_memoized_attributes
    remove_instance_variable(:@number) if defined?(@number)
  end

  # The CWE-XXX number, i.e for CWE-123 this would return 123
  def number
    @number ||= T.must(cwe_id.match(CWE_PATTERN))[1].to_i
  end

  def mitre_link
    self.class.mitre_link(number)
  end

  def self.mitre_link(number)
    "https://cwe.mitre.org/data/definitions/#{number}.html"
  end
end
