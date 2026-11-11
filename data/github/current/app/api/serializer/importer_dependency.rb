# typed: true
# frozen_string_literal: true

module Api::Serializer::ImporterDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  def imported_issue_hash(import_item, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, import_item)
    result = {
      id: import_item.id,
      status: import_item.status,
      url: url("/repos/#{repo}/import/issues/#{import_item.id}", options),
      import_issues_url: url("/repos/#{repo}/import/issues", options),
      repository_url: url("/repos/#{repo}", options),
      created_at: import_item.created_at,
      updated_at: import_item.updated_at,
    }
    if issue = import_item.model
      result.update issue_url: url("/repos/#{repo}/issues/#{issue.number}", options)
    end
    error_data = import_item.import_errors.map { |error| imported_issue_error_hash(error) }
    if error_data.any?
      result.update errors: error_data
    end
    result
  end

  def imported_issue_error_hash(import_item_error)
    {
      location: import_item_error.payload_location,
      resource: import_item_error.resource,
      field: import_item_error.field,
      value: import_item_error.value,
      code: import_item_error.code,
    }
  end
end
