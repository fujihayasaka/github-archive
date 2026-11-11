# typed: strict
# frozen_string_literal: true

# Privacy filter that hides :org_only issue fields from a public project's
# surfaces (column listings, field metadata, item field values).
#
# This is *only* the privacy filter — independent of IssueFieldsFeature flag
# gating. Issue field VALUES on the issue viewer (Issue#issueFieldValues)
# have their own viewer-aware filter; org members can still read :org_only
# values there even when this filter hides the column on project surfaces.
module IssueFieldVisibility
  extend T::Helpers

  sig { params(project: MemexProject, issue_field: T.nilable(Issues::IIssueField)).returns(T::Boolean) }
  def self.visible_on_project_surfaces?(project, issue_field)
    return true if issue_field.nil?
    return true unless project.public?
    issue_field.visibility.to_s != "org_only"
  end

  sig { params(project: MemexProject, columns: T::Array[MemexProjectColumn]).returns(T::Array[MemexProjectColumn]) }
  def self.columns_visible_on_project_surfaces(project, columns)
    return columns unless project.public?
    issue_field_ids = columns.filter_map { |c| c.issue_field_id if c.issue_field? }
    return columns if issue_field_ids.empty?
    hidden = hidden_issue_field_ids_for(project, issue_field_ids)
    return columns if hidden.empty?
    columns.reject { |c| c.issue_field? && hidden.include?(c.issue_field_id) }
  end

  sig { params(project: MemexProject, issue_fields: T::Array[Issues::IIssueField]).returns(T::Array[Issues::IIssueField]) }
  def self.issue_fields_visible_on_project_surfaces(project, issue_fields)
    return issue_fields unless project.public?
    issue_fields.reject { |f| f.visibility.to_s == "org_only" }
  end

  sig { params(project: MemexProject, issue_field_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def self.hidden_issue_field_ids_for(project, issue_field_ids)
    return Set.new unless project.public?
    ids = issue_field_ids.compact.reject(&:zero?)
    return Set.new if ids.empty?
    ::IssueField.where(
      id: ids,
      visibility: ::IssueField::VISIBILITIES[:org_only],
    ).pluck(:id).to_set
  end
end
