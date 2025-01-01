# typed: true
# frozen_string_literal: true

module SlashCommands
  class StructuredIssueCommentCommand < ApplicationSlashCommand
    include NewsiesControllerHelper

    category :custom
    form :schema_based_form
    perform_action :submit_comment

    def self.enabled?(context)
      current_repository = context.current_repository
      return false unless current_repository.structured_issue_comment_templates_enabled?
      return false unless [:issue, :issue_comment, :issue_body].include?(context.surface)
      return false unless context.subject_gid.present?
      return false unless ConfigAsCode::RepoFileTemplate.new_issue_comment_template(current_repository).templates.any?
      true
    end

    def self.triggers(context)
      templates = ConfigAsCode::RepoFileTemplate.new_issue_comment_template(context.current_repository)
      items = templates.templates.map do |template|
        SlashCommands::Trigger.new(
          command: self,
          name: "comment-template-#{template.identifier}",
          title: "📑 " + (template.name.presence || template.filename),
          description: template.about,
          value: template.filename
        )
      end
    end

    def schema_based_form
      templates = ConfigAsCode::RepoFileTemplate.new_issue_comment_template(context.current_repository)
      template = templates[trigger.value]
      if template.nil?
        flash.error = "Invalid option chosen"
        return
      end

      unless template.valid?
        return form(UI::ErrorsComponent.new(template.errors, template.deprecation_warnings, mt: 3, mb: 3))
      end

      form(UI::FormSchema.new(template.body, "command").call, pt: 3)
    end

    def submit_comment
      body = StructuredTemplateWithMetadata.new(data.permit!).to_s
      comment = context.issue.create_comment(context.current_user, body)
      mark_thread_as_read(context.issue, user: context.current_user)
      context.issue.notify_socket_subscribers

      if GitHub.flipper[:meta_data_blobs].enabled?
        GlobalInstrumenter.instrument("meta_data_blob.create",
          actor_id: context.current_user&.id,
          data: JSON.dump(data.to_unsafe_h),
          parent_id: comment.id,
          parent_type: comment.class.to_s,
          submitter_id: self.class.to_s,
          submitter_type: "slash_command"
        )
      end
    end

    # Make things work nicely for `mark_thread_as_read`
    sig { override.returns(T.nilable(T::Boolean)) }
    def logged_in?
      context.current_user != nil
    end
  end
end
