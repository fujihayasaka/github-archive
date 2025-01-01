# typed: true
# frozen_string_literal: true

class PullRequests::Orchestrations::ChangeBase < PullRequestOrchestration
  step :validate_can_change_base do
    return unless pull_request = self.pull_request
    return unless user = self.user

    pull_request.can_change_base_branch!(user, data[:new_base])
  rescue PullRequest::BaseNotChangeableError => e
    [:skipped, e.ui_message]
  end

  job_start

  step :change_base do
    return unless pull_request = self.pull_request
    return unless user = self.user
    return unless new_base = data[:new_base]

    pull_request.change_base_branch(user, new_base)
  rescue PullRequest::BaseNotChangeableError => e
    [:skipped, e.ui_message]
  end
end
