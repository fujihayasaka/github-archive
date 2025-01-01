# typed: strict
# frozen_string_literal: true

class IssueFieldTextValue < IssueFieldValue
  include Issues::IIssueFieldTextValue

  sig { returns(String) }
  def self.sti_name
    "text"
  end

  # Returns the raw value for text fields
  sig { override.returns(String) }
  def value
    raw_value
  end
end
