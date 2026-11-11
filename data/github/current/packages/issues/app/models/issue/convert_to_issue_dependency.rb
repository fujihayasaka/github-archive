# typed: true
# frozen_string_literal: true

module Issue::ConvertToIssueDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  sig { params(position: T::Array[Integer], issue: Issue, user: User, remove: T::Boolean).returns(T::Boolean) }
  def update_issue_body_after_convert_task(position, issue, user, remove: false)
    return false if position.count != 2 && position.any?(&:negative?)

    body_updated = false
    timer = Timer.start

    operation = if remove
      TaskList::RemoveItem.new(position: position)
    else
      TaskList::RenameItem.new(position: position, replacement: "##{issue.number}")
    end

    text = operation.call(T.must(body))

    return false unless text

    body_updated = update_body(text, user)
    timer.stop

    if body_updated
      GitHub.dogstats.distribution("convert_from_task.update_body.duration", timer.elapsed_ms)
    end

    body_updated
  end

  sig { params(position: T::Array[Integer]).returns([T.nilable(String), T.nilable(Issue)]) }
  def get_issue_at_tasklist_position(position)
    result = [T.cast(nil, T.nilable(String)), T.cast(nil, T.nilable(Issue))]
    item_text = TaskList::ParseItemText.new(position: position).call(body)
    return result unless item_text

    result[0] = item_text
    issue_reference = GitHub::IssueReferenceParser.parse_reference(item_text)
    return result unless issue_reference

    nwo, number = issue_reference.values_at(:nwo, :number)
    owner_login, name = nwo&.split("/")

    result[1] = if owner_login && name && number
      parent_repository = Repository.find_by(name: name, owner_login: owner_login)
      parent_issue = parent_repository&.issues&.find_by(number: number)
    else
      repository&.issues&.find_by(number: number)
    end

    result
  end
end
