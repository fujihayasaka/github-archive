# typed: strict
# frozen_string_literal: true

# This controller handles retrieving the available issue fields for a memex project.
# Available issue fields are those that are defined by the project's owning organization.
class Memexes::IssueFields::SuggestedIssueFieldsController < Memexes::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries

  before_action :require_this_memex
  before_action :require_organization_ownership
  before_action :user_has_read_access
  before_action :require_issue_fields_enabled

  sig { void }
  def index
    owner = T.cast(this_memex.owner, Organization)
    fields = Issues.domain.issue_fields.by_organization(owner).filter { |f| MemexProjectColumn.supported_issue_field_type?(f.data_type.to_s) }

    serialized = fields.map do |f|
      {
        id: f.id,
        name: f.name,
        dataType: f.data_type.to_s.camelize(:lower),
        description: f.description,
        priority: f.priority,
      }
    end

    render(json: { issue_fields: serialized })
  end

  private

  sig { void }
  def require_issue_fields_enabled
    return if IssueFieldsFeature.enabled?(this_memex, actor: current_user)
    render_404
  end

  sig { void }
  def require_organization_ownership
    return if this_memex.owner.organization?
    render_404
  end
end
