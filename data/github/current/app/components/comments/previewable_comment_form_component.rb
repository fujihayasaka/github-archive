# typed: true
# frozen_string_literal: true
module Comments
  class PreviewableCommentFormComponent < ApplicationComponent
    include CommentBoxAnalyticsHelper
    include UploadHelper
    include GhostPilotHelper

    delegate :issue_suggestions_params, :mention_suggestions_params, to: :helpers

    renders_one :header, lambda { |tag: :h4, text: "Add a comment"|
      Comments::PreviewableCommentFormComponent::HeaderComponent.new(tag: tag, text: text, header_id: @header_id)
    }

    attr_reader :asset_types,
      :body,
      :comment_id,
      :comment_path,
      :comparison_start_oid,
      :comparison_end_oid,
      :comparison_base_oid,
      :current_repository,
      :field_name,
      :line_number,
      :original_line,
      :placeholder,
      :preview_repository,
      :subject,
      :id,
      :header_id,
      :textarea_id,
      :label,
      :aria,
      :hide_saved_replies,
      :hide_mentions,
      :hide_cross_references,
      :input_max_length,
      :max_length_warning_text,
      :use_fixed_width_font,
      :copilot_text_suggestions_additional_context

    DEFAULT_ASSET_TYPES = [:assets, :"repository-files"].freeze

    def initialize(
      allow_attachments: true,
      allows_suggested_changes: false,
      asset_types: DEFAULT_ASSET_TYPES,
      autofocus: false,
      body: "",
      comment_id: nil,
      comment_path: "",
      preview_path: nil,
      comparison_start_oid: nil,
      comparison_end_oid: nil,
      comparison_base_oid: nil,
      current_repository: nil,
      field_name: "comment[body]",
      hide_nav: false,
      hide_saved_replies: false,
      hide_mentions: false,
      hide_cross_references: false,
      line_number: nil,
      original_line: "",
      placeholder: "Leave a comment", # TODO: change to nil (no placeholder by default) once all use cases are migrated
      preview_repository: current_repository,
      required: true,
      session_resumable: true,
      local_storage_resumable: false,
      show_discussion_validation_errors: false,
      size_to_fit: true,
      size: :small,
      slash_commands_enabled: false,
      slash_commands_surface: nil,
      subject:,
      textarea_id:,
      label: "Comment",
      aria: {},
      input_max_length: nil,
      max_length_warning_text: nil,
      use_fixed_width_font: false,
      tasklist_blocks_enabled: false,
      copilot_summary_enabled: false,
      copilot_text_suggestions_enabled: false,
      copilot_text_suggestions_additional_context: []
    )
      @allow_attachments = allow_attachments
      @allows_suggested_changes = allows_suggested_changes
      @asset_types = asset_types
      @autofocus = autofocus
      @body = body
      @comment_id = comment_id
      @comment_path = comment_path
      @preview_path = preview_path
      @comparison_start_oid = comparison_start_oid
      @comparison_end_oid = comparison_end_oid
      @comparison_base_oid = comparison_base_oid
      @current_repository = current_repository
      @field_name = field_name
      @hide_nav = hide_nav
      @line_number = line_number
      @original_line = original_line
      @placeholder = placeholder
      @preview_repository = preview_repository
      @required = required
      @session_resumable = session_resumable
      @local_storage_resumable = local_storage_resumable
      @show_discussion_validation_errors = show_discussion_validation_errors
      @size_to_fit = size_to_fit
      @size = size
      @slash_commands_enabled = slash_commands_enabled
      @slash_commands_surface = slash_commands_surface
      @subject = subject
      @label = label
      @id = "#{T.must(self.class.name).demodulize.underscore.dasherize}-#{SecureRandom.uuid}"
      @textarea_id = textarea_id || "#{@id}-textarea"
      @header_id = "#{@id}-title"
      @aria = aria
      @hide_saved_replies = hide_saved_replies || subject.is_a?(Gist)
      @hide_mentions = hide_mentions
      @hide_cross_references = hide_cross_references
      @input_max_length = input_max_length
      @max_length_warning_text = max_length_warning_text
      @use_fixed_width_font = use_fixed_width_font
      @tasklist_blocks_enabled = tasklist_blocks_enabled
      @copilot_summary_enabled = copilot_summary_enabled
      @copilot_text_suggestions_enabled = copilot_text_suggestions_enabled
      @copilot_text_suggestions_additional_context = copilot_text_suggestions_additional_context
      raise_if_resumable_conflict
    end

    def use_fixed_width_font?
      @use_fixed_width_font
    end

    def attachment_options
      if current_repository
        { "data-upload-repository-id": current_repository.id }
      elsif subject
        { "data-subject-type": subject.class.name, "data-subject-param": subject }
      else
        {}
      end
    end

    memoize def data_preview_url
      return @preview_path if @preview_path.present?
      preview_path(
        repository: preview_repository.try(:id),
        subject: subject,
        subject_type: subject.class.name,
        markdown_unsupported: false,
      )
    end

    memoize def file_chooser_id
      "fc-#{textarea_id}"
    end

    def discussions_enabled?
      subject.try(:repository).present?
    end

    def write_content_tabpanel
      if allow_attachments?
        file_attachment_tag(
          enabled: true,
          model: :assets,
          class: "js-upload-markdown-image is-default",
          input: "fc-#{textarea_id}",
          role: "tabpanel",
          "aria-labelledby": "write_tab_#{id}",
          "data-tab-container-no-tabstop": true,
          **attachment_options
        ) do |upload_enabled|
          yield(upload_enabled)
        end
      else
        content_tag(:div, role: "tabpanel") do
          yield(false)
        end
      end
    end

    def file_attachment_tag(**args, &block)
      UploadHelper.instance_method(:file_attachment_tag).bind(self).call(**args, &block)
    end

    def gist?
      subject.is_a?(Gist)
    end

    def gist
      gist? ? subject : nil
    end

    def pull_request
      subject.is_a?(PullRequest) ? subject : nil
    end

    def saved_reply_context
      if subject.respond_to?(:new_record?) && subject.new_record?
        "new_#{subject.class.name.underscore}"
      elsif subject.is_a?(PullRequest)
        "pull_request_comment"
      elsif subject.is_a?(Issue)
        "issue"
      end
    end

    def show_discussion_validation_errors?
      @show_discussion_validation_errors
    end

    def show_errors_inline?
      return false if show_discussion_validation_errors?

      subject && subject.errors && subject.errors.any?
    end

    def subject_name
      subject.class.name
    end

    def slash_command_surface
      return unless @slash_commands_enabled
      return @slash_commands_surface if @slash_commands_surface.present?
      SlashCommands.surface_for(subject)
    end

    def suggestion_button_path
      if pull_request && allows_suggested_changes?
        review_comment_suggestion_button_path(subject.repository.owner, subject.repository, subject)
      end
    end

    def text_expander_keys
      [
        ":",
        gist? ? "@" : nil,
        preview_repository ? "@ #" : nil
      ].compact.join(" ")
    end

    def allow_attachments?
      @allow_attachments
    end

    def allows_suggested_changes?
      @allows_suggested_changes
    end

    def autofocus?
      @autofocus
    end

    def hide_nav?
      @hide_nav
    end

    def required?
      @required
    end

    def session_resumable?
      @session_resumable
    end

    def local_storage_resumable?
      @local_storage_resumable
    end

    def size_to_fit?
      @size_to_fit
    end

    def slash_commands_enabled?
      return false unless @slash_commands_enabled
      SlashCommands.supported_surface?(slash_command_surface)
    end

    def tasklist_blocks_enabled?
      @tasklist_blocks_enabled
    end

    def copilot_summary_enabled?
      @copilot_summary_enabled &&
        PullRequests::Copilot.copilot_for_prs_enabled?(current_copilot_user_v2)
    end

    def copilot_text_suggestions_enabled?
      @copilot_text_suggestions_enabled &&
        pull_request.present? &&
        ghost_pilot_available?
    end

    def copilot_text_completion_description
      return unless pull_request.present?
      if @subject.persisted?
        "Pull Request Comment"
      else
        "Pull Request Description"
      end
    end

    def raise_if_resumable_conflict
      if @session_resumable && @local_storage_resumable
        raise ArgumentError.new(
          "You cannot enable both session_resumable and local_storage_resumable! If you are enabling local_storage_resumable, you need to explictly set session_resumable to false, as it defaults to true."
        )
      end
    end

    class HeaderComponent < ApplicationComponent
      def initialize(tag:, text:, header_id:)
        @tag = tag
        @text = text
        @header_id = header_id
      end

      def call
        render(Primer::BaseComponent.new(tag: :div)) do
          render(Primer::BaseComponent.new(tag: :legend)) do
            render(Primer::Beta::Heading.new(tag: @tag, font_size: 4, mb: 2, id: @header_id).with_content(@text))
          end
        end
      end
    end
  end
end
