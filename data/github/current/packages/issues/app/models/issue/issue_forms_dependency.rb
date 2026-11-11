# typed: true
# frozen_string_literal: true

module Issue::IssueFormsDependency
  extend T::Helpers

  attr_accessor :issue_form_params

  requires_ancestor { Issue }

  def instrument_issue_form_creation
    GlobalInstrumenter.instrument(
      "issue_forms.create",
      actor: user,
      data: JSON.dump(issue_form_params),
      issue: self,
      repository: repository,
    )
  end

  def created_from_issue_form?
    issue_form_params.present?
  end
end
