# typed: true
# frozen_string_literal: true

# Defines and interface for objects that can be passed to the Issue.visible_ids and Issue.visible_ids_for methods.
class Issue::Authorizable
  attr_reader :issue_id, :repository_id

  def initialize(issue_id, repository_id)
    @issue_id = issue_id
    @repository_id = repository_id
  end
end
