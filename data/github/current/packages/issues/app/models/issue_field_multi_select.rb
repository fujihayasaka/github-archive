# typed: strict
# frozen_string_literal: true

class IssueFieldMultiSelect < IssueField
  include Issues::IIssueFieldMultiSelect

  # This is needed here instead of the base class so the job properly finds the STI class and destroys the correct associations
  destroy_dependents_in_background :values
  destroy_dependents_in_background :options
  destroy_dependents_in_background :planning_templates_pinned_fields
  destroy_dependents_in_background :planning_templates_type_fields_mappings

  # option with the highest priority (which is the lowest numeric value)
  sig { returns(T.nilable(IssueFieldOption)) }
  def default_option
    options.min_by(&:priority)
  end

  sig { returns(String) }
  def self.sti_name
    "multi_select"
  end
end
