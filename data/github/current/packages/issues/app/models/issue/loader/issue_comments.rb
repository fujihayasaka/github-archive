# typed: true
# frozen_string_literal: true

class Issue::Loader::IssueComments < Issue::Loader::Base
  def initialize(context, issue_comment_ids: [])
    @repository = context.repository
    @issue = context.issue
    @viewer = context.viewer
    @context = context
    @issue_comment_ids = issue_comment_ids
  end

  def self.preload_for(context, issue_comments)
    new(context).preload(issue_comments)
  end

  def self.preload_viewer_can_read_user_content_edits_for(context, issue_comments)
    new(context).preload_viewer_can_read_user_content_edits(issue_comments)
  end

  def preload_comments_reactable_attributes(issue_comments)
    track_execution_time do
      models = issue_comments
      promises = [
        async_preload_attribute(models, :reaction_groups, :async_reaction_groups),
        async_preload_attribute(models, :reaction_path, :async_reaction_path),
      ]

      Promise.all(promises)
    end
  end

  def preload_viewer_can_read_user_content_edits(issue_comments)
    track_execution_time do
      async_preload_attribute(issue_comments, :viewer_can_read_user_content_edits, :async_viewer_can_read_user_content_edits?, [@viewer])
    end
  end

  def preload(issue_comments)
    track_execution_time do
      models = issue_comments

      GitHub::PrefillAssociations.prefill_batch_method(models, :prelude_viewer_can_react, @viewer)
      GitHub::PrefillAssociations.prefill_batch_method(models, :prelude_user_logins_by_reaction)

      promises = []
      promises += [
        async_preload_attribute(models, :viewer_can_react, :prelude_viewer_can_react, [@viewer]),
        async_preload_attribute(models,
                                      :body_html,
                                      :async_body_html,
                                      [],
                                      { context: {
                                        viewer: @viewer,
                                        unfurl_references: true,
                                        cap_filter: @context.cap_filter } }),

        async_preload_attribute(models, :readable_by, :async_readable_by?, [@viewer]),  # needs a new attribute?
        async_preload_attribute(models, :viewer_can_minimize, :async_minimizable_by?, [@viewer]), # needs a new attribute?
        async_preload_attribute(models, :user_is_spammy, :async_user_is_spammy, [@viewer]),
      ]

      if @viewer.try(:site_admin?)
        site_admin_promises = [
          async_preload_attribute(models, :report_count, :async_report_count),
          async_preload_attribute(models, :top_report_reason, :async_top_report_reason),
          async_preload_attribute(models, :last_reported_at, :async_last_reported_at),
        ]
        promises = promises + site_admin_promises
      end

      Promise.all(promises).sync
    end
  end
end
