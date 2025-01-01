# typed: true
# frozen_string_literal: true

class Issue::Loader::CommentLoader < Issue::ShowLoader

  def self.issue_adapter(loader)
    Issue::Adapter::IssueAdapter.new(
      loader.context,
      skip_timeline: true,
    )
  end

  def initialize(issue, repository, viewer, comment: nil, pagination_params: {}, cap_filter: nil, cpu_timer: nil)
    @comment = comment
    super(issue, repository, viewer, pagination_params: pagination_params, cap_filter: cap_filter, cpu_timer: cpu_timer)
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

    preload_repository
    preload_hierarchy if FeatureFlag.vexi.enabled_or_raise?(:tasklist_block_precache, @context.issue.repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    unless @comment.nil?
      # Preload a bunch of `viewer_can_*` attributes
      @comment.preload_viewer_attributes(@context.viewer, @context.repository)
      # GitHub::PrefillAssociations.prefill_associations([@comment], :repository, available_records: [@context.repository])
      # Preload body_html
      async_preload_attribute([@comment],
        :body_html,
        :async_body_html,
        [],
        {
          context: {
            viewer: @context.viewer,
            unfurl_references: true,
            cap_filter: @context.cap_filter,
          }
        }
      ).sync

      # We only ever load one specific comment
      @context.comments_by_id[@comment.id] = @comment
    end

    preload_reactable_attributes
    load_reaction_groups(@context.issue.reaction_groups + @context.comments.map(&:reaction_groups).flatten)

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
