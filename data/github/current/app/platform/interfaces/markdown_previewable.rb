# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module MarkdownPreviewable
      include Platform::Interfaces::Base

      description "Entities that support markdown preview"
      required_capabilities [:mobile_only_schema_mask]

      MAX_CONTENT_SIZE = 400.kilobytes

      field :markdown_preview, Scalars::HTML, required_capabilities: [:mobile_only_schema_mask], description: "An HTML preview of the object's body text", null: false do
        argument :text, String, required: false, description: "The markdown body text to preview", default_value: ""
        argument :subject_type, Enums::MarkdownPreviewSubjectType, required: false, default_value: nil, description: "The subject type of a new object that is being created, not required for existing subjects"
        argument :hide_code_blobs, Boolean, "Whether or not to include the HTML for code blobs", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_suggested_changes_as_text, Boolean, "Whether or not to include the HTML for suggested changes", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :include_suggested_changes_id, Boolean, "Whether or not to include a suggested changes ID in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :scrub_video, Boolean, "Whether or not to turn video tags into links in the HTML", required: false, default_value: true, required_capabilities: [:mobile_only_schema_mask]
        argument :unfurl_references, Boolean, "Whether or not to turn references into status icon and title in the HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_mobile_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks using Mobile-specific HTML", required: false, default_value: false, required_capabilities: [:mobile_only_schema_mask]
        argument :render_tasklist_blocks, Boolean, "Whether or not to render tasklist blocks", required: false, default_value: false, visibility: :internal
      end

      def markdown_preview(
        text: "",
        hide_code_blobs: false,
        render_suggested_changes_as_text: false,
        scrub_video: true,
        unfurl_references: false,
        include_suggested_changes_id: false,
        render_mobile_tasklist_blocks: false,
        render_tasklist_blocks: false,
        subject_type: nil
      )
        if text.bytesize > MAX_CONTENT_SIZE
          return Platform::Errors::Unprocessable.new(
            "This API renders Markdown text up to 400 KB in size. The requested text is too large to render via the API."
          )
        end

        return Promise.resolve(GitHub::HTMLSafeString::EMPTY) if text.empty?

        # body context is only supported if the object is persisted and has a body
        previewing = !supports_body_context?

        options = {
          unfurl_references:,
          hide_code_blobs:,
          scrub_video:,
          render_mobile_tasklist_blocks:,
          render_tasklist_blocks:,
          previewing:, # Used for the tasklist blocks Goomba filter
        }

        if previewing
          # we're in a repo context and creating a new object (Issue, PR, Discussion)
          raise Platform::Errors::ArgumentError.new("subjectType is required when the parent object does not have a description") unless subject_type

          async_repo_context(subject_type).then do |repo_context|
            async_to_html(text, repo_context, options)
          end
        else
          if @object.instance_of?(PullRequest)
            async_pull_request_body_context(@object).then do |body_context|
              async_to_html(text, body_context, options)
            end
          else
            @object.async_body_context.then do |body_context|
              async_to_html(text, body_context, options)
            end
          end
        end
      end

      private

      def supports_body_context?
        @object.respond_to?(:async_body_context) || @object.instance_of?(PullRequest)
      end

      def async_pull_request_body_context(pull)
        pull.async_issue.then do |issue|
          issue.async_repository.then do |repo|
            repo.async_owner.then do
              issue.async_body_context
            end
          end
        end
      end

      def async_to_html(text, obj_context, options)
        obj_context.merge(@context).then do |render_context|
          GitHub::Goomba::MarkdownPipeline.async_to_html(text, render_context.merge(options), nil)
        end
      end

      def async_repo_context(subject_type)
        Promise.all([
          @object.respond_to?(:async_organization) ? @object.async_organization : Promise.resolve(nil),
          @object.respond_to?(:async_entity) ? @object.async_entity : Promise.resolve(nil)
        ]).then do |organization, entity|
          entity ||= @object if @object.instance_of?(Repository)

          {
            subject_type: subject_type,
            entity: entity,
            organization: organization,
            current_user: @context[:viewer],
            base_url: GitHub.url,
            asset_root: "#{GitHub.asset_host_url}/images/icons",
            asset_proxy: GitHub.image_proxy_url,
            disable_asset_proxy: !GitHub.image_proxy_enabled?,
            location: subject_type,
          }
        end
      end
    end
  end
end
