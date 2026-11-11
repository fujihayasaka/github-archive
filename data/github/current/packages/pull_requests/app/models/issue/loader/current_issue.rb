# typed: true
# frozen_string_literal: true

class Issue::Loader::CurrentIssue < Issue::Loader::Base
  def initialize(context)
    @context = context
    @repository = context.repository
    @issue = context.issue
    @viewer = context.viewer
  end

  def self.load_for(context)
    super new(context)
  end

  def self.preload_viewer_can_read_user_content_edits_for(context)
    new(context).preload_viewer_can_read_user_content_edits
  end

  def preload_reactable_attributes
    track_execution_time do
      models = [@issue]

      promises = [
        async_preload_attribute(models, :reaction_groups, :async_reaction_groups),
        async_preload_attribute(models, :reaction_path, :async_reaction_path),
      ]

      Promise.all(promises)
    end
  end

  def preload_viewer_can_read_user_content_edits
    track_execution_time do
      async_preload_attribute([@issue], :viewer_can_read_user_content_edits, :async_viewer_can_read_user_content_edits?, [@viewer])
    end
  end

  def load
    models = [@issue]
    promises = []
    unless @issue.instance_variable_get("@viewer_can_update")
      preload_viewer_can_update_promise = async_preload_attribute(models, :viewer_can_update, :async_viewer_can_update?, [@viewer]).catch do
        Promise.resolve(false)
      end

      promises = promises + [preload_viewer_can_update_promise]
    end
    preload_viewer_can_react_promise = async_preload_attribute(models, :viewer_can_react, :async_viewer_can_react?, [@viewer]).catch do
      Promise.resolve(false)
    end
    promises = promises + [
      async_preload_attribute(models, :can_comment, :async_can_comment?, [@viewer]),
      async_preload_attribute(models,
                              :body_html,
                              :async_body_html,
                              [],
                              { context: {
                                viewer: @viewer,
                                unfurl_references: true,
                                cap_filter: @context.cap_filter } }),
      async_preload_attribute(models, :lightweight_task_list_item_count, :async_task_list_item_count),
      preload_viewer_can_react_promise,
      async_preload_attribute(models, :is_transfer_in_progress, :async_is_transfer_in_progress?),
      async_preload_attribute(models, :close_issue_references, :async_close_issue_references)
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
