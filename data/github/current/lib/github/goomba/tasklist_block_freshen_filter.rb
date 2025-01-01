# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba node filter that freshens tasklists rendered from markdown.
  # Uses up-to-date data from issues-graph when available, and falls back to the markdown pipeline results when not.
  class TasklistBlockFreshenFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "pre[lang='[tasklist]']")

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:tasklist_block,
        :tasklist_block_markdown_at_rest,
        :tasklist_block_nested_html_pipeline,
        :tasklist_block_precache,
        :tasklist_block_soft_limits,
        :tasklist_block_hard_limits]
    end

    def self.enabled?(context)
      return false if context[:disable_issues_graph] == true
      return false unless context[:entity].is_a?(Repository)

      # As we do not support cross-references yet, we do not need to unfurl the
      # tasklist block if the subject is not a persisted issue.
      # Issue comment previews will have a subject_type populated, but not subject.
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"

      return false unless GitHub.flipper[:tasklist_block].enabled?(context[:entity].owner)
      return false if GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
      return false unless GitHub.flipper[:tasklist_block_nested_html_pipeline].enabled?(context[:entity].owner) &&
        GitHub.flipper[:tasklist_block_markdown_at_rest].enabled?(context[:entity].owner)

      return false if context[:for_email] == true
      return false if redundant_call?(context)

      true
    end

    # Private: Determine if calling the filter is redundant.
    #
    # Freshen filter doesn't need to run during a save operation since we will
    # not be producing HTML to save to the database. To do so would lead to
    # extra calls to the issues-graph API with no benefit.
    #
    # During the save operation on an issue we can rely on body html being
    # generated on the load of the issue object for the response.
    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    private_class_method def self.redundant_call?(context)
      # HACK: this is awful 🙀
      #
      # The graphql API does not re-run the HTML pipeline like the web view and
      # so we will rely for the moment on the mobile tasklist block flag being
      # passed in to know we indeed want to render the tasklist block.
      #
      # Related https://github.com/github/mobile-api/issues/229
      return false if context[:render_mobile_tasklist_blocks] || context[:render_tasklist_blocks]
      return false unless context[:subject]

      context[:subject].saved_changes?
    end

    def initialize(*args)
      super
      @counter = 0
      @tasklist_block_hard_limits_enabled = GitHub.flipper[:tasklist_block_hard_limits].enabled?(context[:entity].owner)
      @limiter = TasklistBlocks::Limiter.new(@tasklist_block_hard_limits_enabled, GitHub.flipper[:tasklist_block_soft_limits].enabled?(context[:entity].owner))
      result[:tasklist_block_errors] ||= []
    end

    def call(node)
      new_contents = expand_tasklist_block
      doc = if new_contents.present?
        GitHub.dogstats.increment(
          "issues.tracking_blocks.render.unfurl",
          tags: [
            "result:success",
            "filter:#{self.class.name}",
          ]
        )
        instrument_tasklist_block_render

        Goomba::DocumentFragment.new(new_contents)
      else
        node
      end

      @counter += 1

      doc
    end

    private

    # Fetch remote tasklist blocks from the hierarchy for the subject.
    #
    # Returns IssuesGraph::Proto::GetIssueResponse
    def remote_tasklist_blocks
      return @remote_tasklist_blocks if defined?(@remote_tasklist_blocks)

      remote_tasklist_blocks = context[:subject]&.remote_tracking_blocks
      unless remote_tasklist_blocks
        GitHub.dogstats.increment(
          "issues.tracking_blocks.render.unfurl",
          tags: [
            "result:error",
            "filter:#{self.class.name}"
          ]
        )
      end

      @remote_tasklist_blocks = remote_tasklist_blocks
    end

    def hierarchy_query_type
      @hierarchy_query_type ||= context[:subject].hierarchy_query_type
    end

    def hierarchy_response_source_type
      @hierarchy_response_source_type ||= context[:subject].hierarchy_response_source_type
    end

    def viewer_can_push?(repository)
      return @viewer_can_push if defined?(@viewer_can_push)

      @viewer_can_push = repository.pushable_by?(context[:viewer])
    end

    # Private: Generate HTML for the tasklist block.
    # If we are in the preview context or the call to issues-graph fails, use the pipeline result.
    # Otherwise, use the issues-graph response.
    #
    # Returns nothing.
    def expand_tasklist_block
      return generate_html_from_pipeline_result unless !context[:previewing] && context[:subject] && remote_tasklist_blocks
      generate_html_from_issues_graph
    end

    # Private: Safely return the nested tasklist block item at the given tasklist block
    # and item index
    #
    # Returns string
    def get_tasklist_block_item(result, index)
      return unless result[:tasklist_blocks]
      return unless result[:tasklist_blocks][@counter]
      return unless result[:tasklist_blocks][@counter].items

      result[:tasklist_blocks][@counter].items[index]
    end

    def get_redactor(issues)
      TasklistBlocks::Redactor.new(
        viewer: context[:viewer],
        issues: issues,
        cap_filter: context[:cap_filter],
      )
    end

    # Private: Generates an HTML string for a tasklist block based on the issues
    # & draft issues stored in the Hierarchy.
    #
    # tasklist_block - The IssuesGraph::Proto::TrackingBlock object.
    #
    # Returns String.
    def generate_html_from_issues_graph
      unless tasklist_block = remote_tasklist_blocks[@counter]
        GitHub.dogstats.increment("issues.tracking_blocks.render.unfurl.missing")
        return generate_html_from_pipeline_result
      end

      repository = context[:entity]
      item = context[:subject] # issue
      issues = tasklist_block.issues.map.with_index do |proto_issue, index|
        issue = TasklistBlocks::Issue.from_proto(issue: proto_issue)
        tasklist_block_item = get_tasklist_block_item(result, index)

        # Check if there was any markdown in the draft title, store it for rendering in the view
        if tasklist_block_item && tasklist_block_item.is_a?(TrackingBlocks::DraftIssue)
          issue.title_html = tasklist_block_item.title_html
          issue.original_text = tasklist_block_item.draft_issue
        end

        issue
      end
      redactor = get_redactor(issues)
      current_viewer = context.has_key?(:viewer) ? context[:viewer] : context[:current_user]

      #TODO: (tech debt)
      # - tasklist block parent id: currently, the tasklist block doesn't have a reference to
      #               its parent, so the item.number is passed in to allow editing for now
      view_component = component_class.new(
        id: tasklist_block.key.primaryKey.uuid,
        title: result[:tasklist_blocks][@counter]&.name,
        title_html: result[:tasklist_blocks][@counter]&.name_html,
        validation_msg: validation_msg,
        items: redactor.issues.map(&:to_h),
        hierarchy_completion: item.hierarchy_completion,
        hierarchy_query_type: hierarchy_query_type,
        hierarchy_response_source_type: hierarchy_response_source_type,
        render_context: TrackingBlocks::RenderContextBlock.new(
          current_owner_login: repository.owner_display_login,
          current_repository_name: repository.name,
          current_repository_owner: repository.owner,
          current_item_display_number: item.number,
          current_viewer_can_update: item.viewer_can_update?(current_viewer),
          current_viewer_write_access: viewer_can_push?(repository)
        ),
        current_user: context[:viewer],
        options: {
          tasklist_block_markdown_at_rest_enabled: GitHub.flipper[:tasklist_block_markdown_at_rest].enabled?(repository.owner),
          tasklist_block_hard_limits_enabled: @tasklist_block_hard_limits_enabled
        }
      )

      ApplicationController.render(view_component, formats: [:html], layout: false)
    end

    # Private: Generates an HTML string for a tasklist block based on the issues
    # & draft issues parsed via the markdown pipeline.
    # Supports both preview and graceful failure.
    #
    # tasklist_block - The TasklistBlocks::TasklistBlock object.
    #
    # Returns String.
    def generate_html_from_pipeline_result
      unless tasklist_block = result[:tasklist_blocks][@counter]
        GitHub.dogstats.increment("issues.tracking_blocks.render.unfurl.missing")
        return
      end

      unless context[:previewing]
        tasklist_block.validation_msg = "server_error"
        GitHub.logger.error(
          "Tasklist block validation error",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.request_id": GitHub.context[:request_id],
          "gh.actor_id": GitHub.context[:actor_id],
          "gh.catalog_service": "github/issues-graph",
          "error_type": "server_error",
          "repository_id": repository.id,
          "issue_id": context[:subject].id,
        )
        GitHub.dogstats.increment(
          TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION,
          tags: ["type:server_error"]
        )
      end

      issues = tasklist_block.items.map(&:to_tasklist_issue)
      redactor = get_redactor(issues)
      view_component = component_class.new(
        id: SecureRandom.uuid,
        title: tasklist_block.name,
        title_html: tasklist_block.name_html,
        validation_msg: validation_msg,
        items: redactor.issues.map(&:to_h),
        readonly: true,
        render_context: TrackingBlocks::RenderContextBlock.new(
          current_owner_login: repository.owner_display_login,
          current_repository_name: repository.name,
          current_repository_owner: repository.owner,
        ),
        current_user: context[:viewer],
        options: {
          tasklist_block_markdown_at_rest_enabled: GitHub.flipper[:tasklist_block_markdown_at_rest].enabled?(repository.owner)

        }
      )
      ApplicationController.render(view_component, formats: [:html], layout: false)
    end

    # Private: emit event for rendering a tasklist block, for publishing Hydro
    # events.
    #
    # Returns nothing.
    def instrument_tasklist_block_render
      GlobalInstrumenter.instrument("tasklist.render", {
        viewer: context[:current_user],
        issue_repository: context[:entity],
        issue: context[:subject],
        item_count: item_count,
        render_target: render_target,
      })
    end

    sig { returns(Integer) }
    def item_count
      return 0 unless remote_tasklist_blocks

      remote_tasklist_blocks[@counter]&.issues&.size || 0
    end

    sig { returns(Symbol) }
    def render_target
      if context[:render_mobile_tasklist_blocks]
        :MOBILE
      else
        :WEB
      end
    end

    sig do
      returns(
        T.any(
          T.class_of(TrackingBlocks::TrackingBlockComponent),
          T.class_of(TrackingBlocks::TrackingBlockMobileComponent),
        )
      )
    end
    def component_class
      if context[:render_mobile_tasklist_blocks]
        TrackingBlocks::TrackingBlockMobileComponent
      else
        TrackingBlocks::TrackingBlockComponent
      end
    end

    sig { returns(T.nilable(String)) }
    def validation_msg
      return unless tasklist_block = result[:tasklist_blocks][@counter]
      number_of_tasks = tasklist_block.items.length
      number_of_tasklists = @counter + 1
      msg, err = @limiter.check_if_exceed_limit(number_of_tasks, number_of_tasklists)
      result[:tasklist_block_errors] << err if err
      msg || tasklist_block.validation_msg
    end
  end
end
