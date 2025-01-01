# typed: true
# frozen_string_literal: true

class Issue::ShowLayoutLoader < Issue::ShowLoader
  def self.issue_adapter(loader)
    Issue::Adapter::IssueAdapter.new(loader.context)
  end

  def preload
    [
      :comments_by_id,
      :cross_references_by_id,
      :events_by_id,
      :repositories_by_id,
      :projects_by_id,
    ].each do |symbol|
      @context.preload_attr(symbol, {})
    end

    @reaction_groups = {}

    preload_repository
    load_latest_user_content_edit
    load_users
    load_integrations
    load_integration_users
    attach_user_associations
    attach_performed_via_integrations
    load_authors_association
    attach_integrations
    preload_bots
    preload_primary_avatars
    preload_issue
    preload_owner_settings
  end
end
