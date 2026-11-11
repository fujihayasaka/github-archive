# typed: strict
# frozen_string_literal: true

class IssueFieldDate < IssueField
  include Issues::IIssueFieldDate
  validates_absence_of :options, message: "Date fields do not support options"

  # This is needed here instead of the base class so the job properly finds the STI class and destroys the correct associations
  destroy_dependents_in_background :values
  destroy_dependents_in_background :planning_templates_pinned_fields
  destroy_dependents_in_background :planning_templates_type_fields_mappings

  sig { returns(String) }
  def self.sti_name
    "date"
  end
end
