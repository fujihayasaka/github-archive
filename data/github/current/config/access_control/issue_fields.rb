# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_issue_fields do |access|
    # Allow everyone (including anonymous users) to read issue fields within the context of a repository if:
    #  - The provided repository -or- issue's repository is public
    access.allow :everyone do |context|
      repo = context[:current_repo] || context[:current_issue]&.repository
      repo && repo.public?
    end

    access.allow :issue_field_reader

    access.ensure_context :resource
  end
end
