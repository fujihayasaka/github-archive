# typed: strict
# frozen_string_literal: true

class IssueFieldNumber < IssueField
  include Issues::IIssueFieldNumber
  validates_absence_of :options, message: "Number fields do not support options"

  sig { returns(String) }
  def self.sti_name
    "number"
  end
end
