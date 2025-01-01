# typed: true
# frozen_string_literal: true

module Issue::ConvertToIssueDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  extend T::Sig

  requires_ancestor { Issue }

  sig { params(position: T::Array[Integer], issue: Issue, user: User).returns(T::Boolean) }
  def update_issue_body_after_convert_task(position, issue, user)
    return false if position.count != 2 && position.any?(&:negative?)

    body_updated = false
    timer = Timer.start

    operation = TaskList::RenameItem.new(position: position, replacement: "##{issue.number}")

    text = operation.call(body)

    return false unless text

    body_updated = update_body(text, user)
    timer.stop

    if body_updated
      GitHub.dogstats.distribution("convert_from_task.update_body.duration", timer.elapsed_ms)
    end

    body_updated
  end
end
