# typed: true
# frozen_string_literal: true

module Comments
  class PreviewableCommentFormComponent < ApplicationComponent
    include CommentBoxAnalyticsHelper
    include UploadHelper
    include GitHub::ResilienceMixin

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
      :upload_repository_id,
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
      :use_fixed_width_font

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
      upload_repository_id: nil, # Used when we know the upload target but don't want to look up the repository (e.g. in internal feedback form)
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
      is_copilot_mention_indicator_visible: false,
      is_copilot_code_review_hint_visible: false
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
      @upload_repository_id = upload_repository_id
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
      @is_copilot_mention_indicator_visible = is_copilot_mention_indicator_visible
      @is_copilot_code_review_hint_visible = is_copilot_code_review_hint_visible
      raise_if_resumable_conflict
    end

    def use_fixed_width_font?
      @use_fixed_width_font
    end

    def attachment_options
      if upload_repository_id
        { "data-upload-repository-id": upload_repository_id }
      elsif current_repository
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

    def is_copilot_mention_indicator_visible?
      @is_copilot_mention_indicator_visible
    end

    def is_model_picker_enabled?
      @is_copilot_mention_indicator_visible &&
        logged_in? &&
        FeatureFlag.vexi.enabled?(:coding_agent_model_selection, current_user, default: false) &&
        FeatureFlag.vexi.enabled?(:copilot_swe_agent_pr_comment_model_picker, current_user, default: false)
    end

    memoize def token_based_billing_enabled_for_copilot_mention?
      return false unless is_model_picker_enabled?

      copilot_user = current_copilot_user_v2
      return false unless copilot_user

      # The Copilot cluster is an optional dependency for this view; if it is
      # unavailable, fall back to treating the user as not on token-based
      # billing rather than failing the whole comment form render.
      with_database_error_fallback(fallback: false) do
        copilot_user.use_token_based_billing?
      end
    end

    def coding_agent_models_url
      return nil unless preview_repository
      return nil unless helpers.respond_to?(:repo_coding_agent_models_path)
      options = {
        user_id: preview_repository.owner.display_login,
        repository: preview_repository.name,
      }
      options[:pull_id] = pull_request.id if pull_request
      helpers.repo_coding_agent_models_path(options)
    end

    memoize def agent_mention_tokens
      return nil unless preview_repository
      return nil if eligible_mention_agents.empty?

      # Token format: "<token>:<vendor>:<slug>:<URI-encoded display_name>[:<authorization_status>]"
      # `vendor` may be empty for 3rd-party agents that don't participate in the model-picker UX.
      include_status = agent_authorization_status_field_enabled?
      tokens = eligible_mention_agents.flat_map do |agent|
        # 3p agents without model_vendors still get a single token (empty vendor) so the
        # composer can recognize the @mention and mount the authorization banner.
        vendors = agent.model_vendors
        vendors = [""] if vendors.empty?
        vendors.map do |vendor|
          parts = [
            AgenticApp.mention_token(agent),
            vendor,
            agent.slug,
            ERB::Util.url_encode(agent.display_name),
          ]
          parts << agent_authorization_status_for(agent) if include_status
          parts.join(":")
        end
      end
      tokens.join(",") if tokens.any?
    end

    # The set of agents whose @mentions should be recognized by the composer. Combines:
    #   - Claude + Codex when the model picker is enabled (legacy v1 behavior)
    #   - All mentionable third-party agentic apps installed on the repo when the
    #     `copilot_swe_agent_authorization_status` consent flag is on
    # Deduped by slug so Claude/Codex aren't emitted twice when also exposed as
    # mentionable agents via the enabled_for_repository registry.
    memoize def eligible_mention_agents
      legacy = if is_model_picker_enabled? &&
                  FeatureFlag.vexi.enabled?(:coding_agent_third_party_model_ui, preview_repository, default: false)
        [AgenticApp::ClaudeAgent.instance, AgenticApp::CodexAgent.instance]
      else
        []
      end

      # Both `AgenticApp.all_agents` and `enabled_for_repository?` hit the
      # optional ApplicationRecord::Copilot cluster; degrade gracefully if it
      # is unavailable rather than 500ing the entire composer.
      third_party = with_database_error_fallback(fallback: []) do
        if agent_authorization_status_field_enabled? && current_user && preview_repository
          AgenticApp.all_agents.select do |agent|
            next false if agent.partner_agent?
            next false if agent.global?
            next false unless agent.mentionable?

            agent.enabled_for_repository?(preview_repository, current_user)
          end
        else
          []
        end
      end

      (legacy + third_party).uniq(&:slug)
    end

    # Batch-computes authorization status for every eligible agent in a single pass.
    # Calls each agent's `.integration` exactly once and makes one batched
    # `NeedsAuthorizationLookup` query, avoiding the per-agent N+1 that would occur
    # if each `agent_authorization_status_for` call queried independently.
    memoize def agent_authorization_status_map
      result = {}
      return result unless current_user
      return result unless agent_authorization_status_field_enabled?

      integration_id_by_slug = {}
      eligible_mention_agents.each do |agent|
        integration = agent.integration
        if integration
          integration_id_by_slug[agent.slug] = integration.id
        else
          result[agent.slug] = "authorized"
        end
      end

      integration_ids = integration_id_by_slug.values
      if integration_ids.any?
        needs_auth_ids = ::AgenticApp::NeedsAuthorizationLookup.for_integration_ids(
          user: current_user,
          integration_ids: integration_ids,
        )
        integration_id_by_slug.each do |slug, int_id|
          result[slug] = needs_auth_ids.include?(int_id) ? "needs_authorization" : "authorized"
        end
      end

      result
    rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError, ActiveRecord::ConnectionNotEstablished
      # Degrade gracefully if the Copilot DB connection is unavailable: skip the
      # consent prompt rather than 500ing the composer. The picker lock + the
      # server-side runtime gate in sweagentd still enforce consent at job time.
      {}
    end

    # Returns "authorized" or "needs_authorization" for the viewer's per-user OAuth grant
    # on the agent's integration. Consults the memoized batch map rather than querying
    # per agent. Anonymous viewers are treated as needing authorization (defensive).
    # Agents without an integration require no OAuth consent.
    sig { params(agent: T.untyped).returns(String) }
    def agent_authorization_status_for(agent)
      return "needs_authorization" unless current_user
      agent_authorization_status_map[agent.slug] || "authorized"
    end

    sig { returns(T::Boolean) }
    def agent_authorization_status_field_enabled?
      FeatureFlag.vexi.enabled?(:copilot_swe_agent_authorization_status, current_user, default: false)
    end

    # True when the composer has any agent mention tokens AND at least one of those
    # agents needs authorization from the current viewer. When all configured agents
    # are already authorized, skip mounting the banner partial entirely — no event
    # could fire that the partial would react to.
    def agent_authorization_banner_partial_available?
      return false unless agent_mention_tokens
      return false unless agent_authorization_status_field_enabled?
      eligible_mention_agents.any? do |agent|
        agent_authorization_status_for(agent) == "needs_authorization"
      end
    end

    # True when the composer should mount the React partial that fetches
    # `/copilot/agent-sessions/quota-snapshot` and dispatches the
    # `copilot-mention-quota-status` window event consumed by the
    # `<copilot-mentions-hint>` element to gate submission.
    #
    # Gated on the same feature flag as `Copilot::Users::AgentQuotaSnapshot#build`
    # so we only mount the partial for viewers where the endpoint will return a
    # useful payload. This also doubles as deploy-safety: the github-ui bundle
    # rolls out before the flag flips, so we never try to expand a missing JS
    # bundle in production.
    sig { returns(T::Boolean) }
    def copilot_quota_banner_partial_available?
      return false unless agent_mention_tokens
      return false unless current_user
      FeatureFlag.vexi.enabled?(:copilot_coding_agent_tbb_quota_banner, current_user, default: false)
    end

    def copilot_mention_indicator_text
      # `authored_by_agent?` hits the Copilot cluster (`AgenticApp.agent_for_bot_id`),
      # which is optional. Fall back to `false` so this banner copy degrades to the
      # default rather than 500ing the comment form when Copilot is unavailable.
      authored_by_agent = with_database_error_fallback(fallback: false) { pull_request&.authored_by_agent? }
      if authored_by_agent || FeatureFlag.vexi.enabled?(:copilot_swe_agent_work_on_current_branch, current_user, default: false)
        "Agent pushes its changes to this branch"
      else
        "Agent opens a new pull request against this branch"
      end
    end

    def is_copilot_code_review_hint_visible?
      @is_copilot_code_review_hint_visible &&
        logged_in? &&
        ::Copilot::CodeReview::Features.reply_hint_enabled?(T.must(current_copilot_user_v2))
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
