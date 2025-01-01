# typed: true
# frozen_string_literal: true

# Renders the form for adding or updating a branch or tag gate rule.
# Use this component as the content of a DialogComponent. It contains both a body and footer.
class Environments::EditBranchOrTagGateRuleFormComponent < ApplicationComponent
  def initialize(form_method:, form_path:, submit_button_text:, submit_button_disable_text:, name: "", policy_type: "", matchings: [])
    @form_method = form_method
    @form_path = form_path
    @submit_button_text = submit_button_text
    @submit_button_disable_text = submit_button_disable_text
    @name = name
    @policy_type = policy_type
    @matchings = matchings
  end

  def new_branch_rule?
    @name.empty?
  end
end
