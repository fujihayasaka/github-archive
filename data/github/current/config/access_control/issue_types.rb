# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_issue_types do |access|

    # Allow everyone (including anonymous users) to read an issue type within the context of a repository if:
    #  - The provided repository -or- issue's repository is public
    #  - The issue type is enabled
    access.allow :everyone do |context|
      repo = context[:current_repo] || context[:current_issue]&.repository
      repo && repo.public? && context[:issue_type].enabled?
    end

    access.allow :issue_type_reader
  end
end
