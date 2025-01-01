# typed: strict
# frozen_string_literal: true

module Issue::SummariesDependency
  extend T::Helpers

  requires_ancestor { Issue }

  sig { params(actor: User).returns(IssueSummary) }
  def queue_summary(actor:)
    existing_summary = self.issue_summaries.where(user: actor).first
    if existing_summary.nil?
      self.issue_summaries.create(user: actor)
    else
      existing_summary.reset_and_schedule
      existing_summary
    end
  end
end
