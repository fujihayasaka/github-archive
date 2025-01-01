# typed: strict
# frozen_string_literal: true

class IssueFieldSingleSelect < IssueField
  include Issues::IIssueFieldSingleSelect

  # This is needed here instead of the base class so the job properly finds the STI class and destroys the correct associations
  destroy_dependents_in_background :values
  destroy_dependents_in_background :options

  sig { returns(String) }
  def self.sti_name
    "single_select"
  end
end
