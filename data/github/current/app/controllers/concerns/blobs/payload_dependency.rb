# typed: true
# frozen_string_literal: true

module Blobs
  module PayloadDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    include GitHub::Memoizer
    include CopilotInfoHelper

    requires_ancestor { BlobController }

    def blob_layout_payload(view)
      if current_repository.feature_flag_enabled?(:code_view_track_blob_size, default: false)
        GitHub.dogstats.distribution(
          "code_view.blob.size",
          current_blob.data.size,
          tags: ["logged_in:#{logged_in?}", "robot:#{robot?}", "layout:true"]
        )
      end

      @editor_configs = load_blob_editor_configs!(current_commit, current_blob) unless degrade_editor_config_retrieval_enabled?

      payload_tags = ["payload_type: blob_layout"]
      GitHub.dogstats.distribution_time("repos.payload.time", tags: payload_tags) do
        if is_codeowners_file? && !current_repository.plan_supports?(:codeowners)
          show_plan_support_banner = true
          repo_owned_by_current_user = current_repository.owner == current_user
          repo_is_fork = current_repository.fork?
          if repo_owned_by_current_user && !repo_is_fork
            upgrade_path = plan_upgrade_path
            upgrade_data_attributes = feature_gate_upsell_click_attrs(:codeowners, user: current_user)
          end
          if !repo_owned_by_current_user
            show_free_org_gated_feature_message = show_free_org_gated_feature_message?(current_repository, current_user)
            if show_free_org_gated_feature_message
              upgrade_path = upgrade_path(org: current_repository.owner, plan: "business", target: "organization")
              upgrade_data_attributes = feature_gate_upsell_click_attrs(:codeowners, user: current_user)
            end
          end
        end

        file_exists_on_default = tree_name == current_repository.default_branch || current_repository.includes_file?(path_string, current_repository.default_branch)

        payload = {
          codeLineWrapEnabled: code_line_wrap_enabled?,
          refInfo: {
            name: tree_name,
            listCacheKey: ref_list_cache_key,
            canEdit: view.edit_enabled?,
            refType: helpers.tree_type,
            currentOid: commit_sha,
            canEditOnDefaultBranch: view.edit_enabled_for_default_branch?,
            fileExistsOnDefault: file_exists_on_default
          },
          path: path_string,
          blob: {
            copilotSWEAgentEnabled: current_repository.copilot_swe_agent_enabled_with_write_permissions?(current_user),
            dependabotInfo: {
              showConfigurationBanner: !!view.show_dependabot_configuration_banner?,
              configFilePath: view.dependabot_config_file_path,
              networkDependabotPath: GitHub.enterprise? ? nil : network_dependabot_path(current_repository.owner, current_repository),
              dismissConfigurationNoticePath: dismiss_notice_path(UserNotice::DEPENDABOT_CONFIGURATION_NOTICE),
              configurationNoticeDismissed: current_user&.dismissed_notice?(UserNotice::DEPENDABOT_CONFIGURATION_NOTICE),
            },
            displayName: current_blob.display_name,
            displayUrl: blob_display_url(view),
            headerInfo: {
              blobSize: number_to_human_size(current_blob.size),
              deleteTooltip: view.file_action_tooltip(action: :delete),
              editTooltip: view.file_action_tooltip(action: :edit),
              ghDesktopPath: blob_gh_desktop_path(view),
              isGitLfs: current_blob.git_lfs?,
              onBranch: view.branch?,
              shortPath: blob_short_path(current_blob),
              siteNavLoginPath: site_nav_login_path,
              isCSV: is_csv?,
              isRichtext: is_richtext?,
              lineInfo: blob_line_info,
              mode: human_mode(current_blob.mode),
            },
            image: current_blob.image?,
            isCodeownersFile: is_codeowners_file?,
            isPlain: is_plain?,
            isValidLegacyIssueTemplate: view.valid_legacy_template,
            isIssueTemplate: current_blob_issue_template.present?,
            isDiscussionTemplate: is_discussion_template?,
            language: current_blob&.language&.name,
            languageID: current_blob&.language&.language_id,
            large: current_blob.large?,
            planSupportInfo: {
              repoIsFork: repo_is_fork,
              repoOwnedByCurrentUser: repo_owned_by_current_user,
              requestFullPath: request.fullpath,
              showFreeOrgGatedFeatureMessage: show_free_org_gated_feature_message,
              showPlanSupportBanner: show_plan_support_banner,
              upgradeDataAttributes: upgrade_data_attributes,
              upgradePath: upgrade_path
            },
            publishBannersInfo: {
              dismissActionNoticePath: dismiss_notice_path(UserNotice::PUBLISH_ACTION_FROM_DOCKERFILE_NOTICE),
              releasePath: new_release_path_helper(query_params: { marketplace: true }),
              showPublishActionBanner: view.show_publish_action_banner?,
            },
            rawBlobUrl: safe_raw_blob_url,
            renderImageOrRaw: render_image_or_raw?(view.blob),
            shortPath: params[:short_path],
            symbolsEnabled: symbols_enabled?,
            tabSize: blob_tab_size,
            topBannersInfo: {
              overridingGlobalFundingFile: view.overriding_global_funding_file?,
              globalPreferredFundingPath: global_preferred_funding_path(view.repo),
              showInvalidCitationWarning: view.show_invalid_citation_warning?,
              citationHelpUrl: Repositories::Citation.help_url,
              actionsOnboardingTip: actions_onboarding_tip
            },
            truncated: current_blob.truncated?,
            viewable: view.blob.viewable?,
            workflowRedirectUrl: (workflow_yaml_file?) ? filtered_runs_by_file_path(filename: view.filename, lab: view.lab_workflow_file?) : nil,
          },
        }

        timer = Timer.start
        payload[:copilotInfo] = copilot_info_payload(
            CodeView::FileLayout,
            current_repository.organization
          )
        payload[:copilotAccessAllowed] = with_database_error_fallback(fallback: false) do
          helpers.copilot_chat_enabled_for_current_user? && !helpers.copilot_hidden_by_preference?
        end
        payload[:copilotSpacesEnabled] = with_database_error_fallback(fallback: false) do
          CopilotSpaces::Enabled.copilot_spaces_enabled_for_user?(current_user)
        end
        payload[:modelsAccessAllowed] = with_database_error_fallback(fallback: false) do
          GitHubModels::User.new(user: current_user).models_access_allowed_for_blob?(blob: current_blob,
            blob_url: safe_raw_blob_url, repository: current_repository)
        end
        payload[:modelsRepoIntegrationEnabled] = with_database_error_fallback(fallback: false) do
          GitHubModels::Repository.new(repository: current_repository).models_enabled_for_repo?
        end
        payload[:isMarketplaceEnabled] = GitHub.marketplace_enabled?

        GitHub.dogstats.distribution("code_view.blob.settings_time", timer.elapsed_ms, tags: [])

        Repos::CodeViewPayloads::BlobLayoutPayload.new(payload)
      end
    end

    def styled_blob_payload(view)
      payload_tags = ["payload_type: blob_deferred"]
      GitHub.dogstats.distribution_time("repos.payload.time", tags: payload_tags) do
        raw_lines = needs_raw?(view) ? current_blob_lines : nil
        (colorized_lines, styling_directives) = blob_colorize(view, true)

        payload = {
          rawLines: raw_lines,
          stylingDirectives: styling_directives,
          colorizedLines: colorized_lines,
        }

        Repos::CodeViewPayloads::BlobLayoutStyledBlobPayload.new(payload)
      end
    end

    private

    def issue_template_payload(view)
      issue_template = current_blob_issue_template
      issue_template_valid = issue_template&.validate
      issue_template_errors = issue_template&.errors&.map { |error| { message: view.rich_form_message(error.full_message), link: error.options[:docs] } }
      issue_template_inputs = issue_template&.inputs&.map do |input|
        input_hash = input.instance_values
        if input.type == "markdown" && input_hash.has_key?("value")
          input_hash["value"] = GitHub::Goomba::MarkdownPipeline.to_html(input.value)
        elsif input_hash.has_key?("description")
          input_hash["description"] = GitHub::Goomba::MarkdownPipeline.to_html(input.description)
        end
        input_hash
      end

      return nil unless issue_template

      {
        about: issue_template.about,
        assignees: issue_template.assignees_string,
        errors: issue_template_errors,
        inputs: issue_template_inputs,
        labels: issue_template.labels_string,
        projects: issue_template.projects_string,
        name: issue_template.name,
        structured: issue_template.structured?,
        valid: issue_template_valid,
        type: issue_template.type,
      }
    end

    def discussion_template_payload(view)
      discussion_template_errors = view.discussion_template&.errors&.map { |error| { message: view.rich_form_message(error.full_message), link: error.options[:docs] } }

      discussion_template = nil
      discussion_inputs = nil
      if is_discussion_template?
        discussion_template = current_repository.discussion_templates[path_string]
        discussion_inputs = discussion_template&.config&.body&.map do |input|
          input_hash = input.instance_values
          if input.try(:type) == "markdown" && input_hash.has_key?("value")
            input_hash["value"] = GitHub::Goomba::MarkdownPipeline.to_html(input.value)
          elsif input_hash.has_key?("description")
            input_hash["description"] = GitHub::Goomba::MarkdownPipeline.to_html(input.description)
          end
          input_hash
        end
      end

      return nil unless discussion_template

      {
        errors: discussion_template_errors,
        inputs: discussion_inputs,
        labels: discussion_template.config.labels.join(", "),
        title: discussion_template.config.title,
        valid: discussion_template_errors.empty?
      }
    end

    memoize def current_blob_lines
      raw_blob = current_blob.data.size > BlobController::MAX_BLOB_SIZE ? nil : current_blob.data
      raw_blob_lines = raw_blob&.split("\n")
      # Do not include empty lines at the end of a file
      raw_blob_lines.pop if raw_blob_lines&.last&.empty?
      raw_blob_lines
    end

    memoize def is_codeowners_file?
      PreferredFile.is_type?(tree_entry: current_blob, type: :codeowners)
    end

    def blob_colorize(view, needs_colorize)
      styling_directives = nil
      colorized_lines = nil
      user_agent_string = request.user_agent&.slice(0, Browser.user_agent_size_limit - 1)

      if needs_colorize || params[:short_path].present?
        browser_info = Browser.new(user_agent_string)
        should_use_no_virtualization_view = is_correct_browser_and_version_for_inert?(browser_info)

        if should_use_no_virtualization_view &&
            FeatureFlag.vexi.enabled?(:react_blob_overlay, current_user, default: true) &&
            !current_blob_lines.nil? && current_blob_lines.length < 3500 && !code_line_wrap_enabled?
          colorized_lines = current_blob.colorized_lines(strategy: colorize_strategy)
          GitHub.dogstats.increment("gh.render.blob_controller_render_no_virtualization.count")
        else
          styling_directives = current_blob.styling_directives(strategy: colorize_strategy)
          GitHub.dogstats.increment("gh.render.blob_controller_render_virtualization.count")
        end
      end

      [colorized_lines, styling_directives]
    end

    def blob_render_file_type(view)
      @blob_render_file_type ||= {}
      return @blob_render_file_type[view] if @blob_render_file_type.key?(view)

      @blob_render_file_type[view] = begin
        render_file_type = current_blob.render_file_type_for_display(:view) unless blame?
        if view.display_with_code_rendering_service?
          rendering_service = view.code_rendering_service
          render_file_type = rendering_service.render_type
        end
        render_file_type
      end
    end

    def blob_gh_desktop_path(view)
      return unless view.branch?
      app_clone_url(nil, nil, current_branch_or_tag_name, path_string)
    end

    def blob_display_url(view)
      if view.display_with_code_rendering_service?
        rendering_service = view.code_rendering_service
        return rendering_service.url_for_display(commit_oid: current_commit.sha)
      end

      renderable_blob_url(current_blob, current_repository, raw_blob_url)
    end

    def blob_line_info
      # fetch data for the header
      return { truncatedLoc: nil, truncatedSloc: nil } unless current_blob.viewable?

      {
        truncatedLoc: current_blob.truncated_loc,
        truncatedSloc: current_blob.truncated_sloc
      }
    end

    def blob_tab_size
      tab_size(current_blob.path)
    end

    def needs_colorize?(view)
      case
      when blame?
        true
      when current_blob.binary?
      when blob_render_file_type(view)
      when is_csv? && !is_plain?
      when current_blob.symlink?
        false
      else
        true
      end
    end

    memoize def is_csv?
      csv_or_tsv?(current_blob.extname) && !(current_blob.git_lfs_pointer? || current_blob.data.blank?)
    end

    memoize def is_richtext?
      GitHub::HTML::MarkupFilter.can_render_blob?(current_blob)
    end

    def is_plain?
      params[:plain].to_s.in?(%w[1 true])
    end

    memoize def code_line_wrap_enabled?
      logged_in? ? current_user.settings.get(:code_line_wrap_enabled) : false
    end

    memoize def is_discussion_template?
      DiscussionTemplates.valid_path?(path_string)
    end

    def needs_raw?(view)
      @needs_raw ||= {}
      return @needs_raw[view] if @needs_raw.key?(view)

      @needs_raw[view] = (needs_colorize?(view) || current_blob.symlink? || current_blob.render_file_type_for_display(:view) || is_csv?) && view.blob.viewable?
    end
  end
end
