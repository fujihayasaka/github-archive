# typed: strict
# frozen_string_literal: true

class IssueFieldNumber < IssueField
  include Issues::IIssueFieldNumber
  validates_absence_of :options, message: "Number fields do not support options"

  # This is needed here instead of the base class so the job properly finds the STI class and destroys the correct associations
  destroy_dependents_in_background :values
  destroy_dependents_in_background :planning_templates_pinned_fields, sharding_key: :owner_id, sharding_value_key: :owner_id
  destroy_dependents_in_background :planning_templates_type_fields_mappings, sharding_key: :owner_id, sharding_value_key: :owner_id

  sig { returns(String) }
  def self.sti_name
    "number"
  end
end
