# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_issue_fields do |access|
    # Allow everyone (including anonymous users) to read issue fields within the context of a repository if:
    #  - The provided repository -or- issue's repository is public
    access.allow :everyone do |context|
      repo = context[:current_issue]&.repository
      repo && repo.public?
    end

    access.allow :issue_field_reader

    access.ensure_context :resource
  end

  define_access :read_issue_field_values do |access|
    issue_must_be_readable(access)

    # Allow everyone (including anonymous users) to read issue field values if the repository is public.
    access.allow(:everyone) do |context|
      context[:current_issue]&.repository&.public?
    end

    access.allow(:issue_field_value_reader)
  end

  define_access :update_issue_field_values do |access|
    resource_must_belong_to_repo(access)
    issue_must_be_readable(access)
    # a way to require that certain keys are present in the context hash
    access.ensure_context :resource

    access.allow(:issue_writer)
  end
end
