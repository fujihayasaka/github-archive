# typed: strict
# frozen_string_literal: true

class IssueFieldText < IssueField
  include Issues::IIssueFieldText
  validates_absence_of :options, message: "Text fields do not support options"

  # This is needed here instead of the base class so the job properly finds the STI class and destroys the correct associations
  destroy_dependents_in_background :values

  sig { returns(String) }
  def self.sti_name
    "text"
  end
end
