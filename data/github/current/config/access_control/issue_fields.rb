# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_issue_fields do |access|
    access.allow :issue_field_reader

    access.ensure_context :resource
  end

  define_access :read_issue_field_values do |access|
    issue_must_be_readable(access)

    access.allow(:issue_field_value_reader)
  end

  define_access :update_issue_field_values do |access|
    resource_must_belong_to_repo(access)
    issue_must_be_readable(access)
    # a way to require that certain keys are present in the context hash
    access.ensure_context :resource

    access.allow(:issue_field_value_writer)
  end
end
