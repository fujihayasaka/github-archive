# frozen_string_literal: true

class CWE < ApplicationRecord
  self.primary_key = :cwe_id

  scope :with_content_like, lambda { |query|
    with_substring("CONVERT(name USING utf8mb4)", query).or(with_substring("cwe_id", query))
  }

  # Order records by the numeric value of the CWE ID. Otherwise, the CWE-1000
  # appears before CWE-2. The SUBSTRING call takes the numeric portion of the
  # CWE ID as a string and multiplies it by one to convert it to an integer.
  scope :in_numeric_order, -> { order(Arel.sql("SUBSTRING(cwe_id, 5, 4) * 1")) }

  validates :name, presence: true
end
