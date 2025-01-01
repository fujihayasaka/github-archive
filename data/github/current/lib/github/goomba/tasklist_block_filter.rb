# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba node filter that generates HTML for tasklist block "chrome".
  # Also prepares items for parsing by subsequent filters, and a result to be filled in.
  class TasklistBlockFilter < NodeFilter
    extend T::Sig

    # Pattern used for matching tasklist title
    TASKLIST_TITLE_SELECTOR = /(^#*) #{TaskList::Filter::IssueTextPattern}/

    SELECTOR = Goomba::Selector.new(match: "pre[lang='[tasklist]']")

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:tasklist_block,
        :tasklist_block_precache,
        :tasklist_block_input_validation,
        :tasklist_block_soft_limits,
        :tasklist_block_hard_limits]
    end

    def self.cache_key(context)
      hierarchy = context[:subject].try(:hierarchy)
      hierarchy&.issue&.timestamp
    end

    def self.enabled?(context)
      return false if context[:disable_issues_graph] == true
      return false unless context[:entity].is_a?(Repository)

      # As we do not support cross-references yet, we do not need to unfurl the
      # tracking block if the subject is not a persisted issue. Issue
      # comment previews will have a subject_type populated, but not subject.
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"

      return false unless GitHub.flipper[:tasklist_block].enabled?(context[:entity].owner)
      return false if context[:for_email] == true
      GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
    end

    def initialize(*args)
      super
      @counter = 0
      @tasklist_block_validation_enabled = GitHub.flipper[:tasklist_block_input_validation].enabled?(context[:entity].owner)
      @tasklist_block_hard_limits_enabled = GitHub.flipper[:tasklist_block_hard_limits].enabled?(context[:entity].owner)
      @limiter = TasklistBlocks::Limiter.new(@tasklist_block_hard_limits_enabled, GitHub.flipper[:tasklist_block_soft_limits].enabled?(context[:entity].owner))
      result[:tasklist_block_errors] ||= []
    end

    def call(node)
      new_contents = generate_tracking_block_html(node)

      GitHub.dogstats.increment(
        "issues.tracking_blocks.render.unfurl",
        tags: [
          "result:success",
          "filter:#{self.class.name}"
        ]
      )
      instrument_tasklist_block_render

      Goomba::DocumentFragment.new(new_contents)
    end

    private

    # Private: Generates an HTML string for the frame around a tasklist block, and prepares for subsequent parsing of
    # tasklist block items.
    #
    # Returns String.
    def generate_tracking_block_html(node)
      repository = context[:entity]
      item = context[:subject] # issue

      # save original markdown for editing via tasklist UI
      # validate that the tasklist block is well-formed
      original_title, original_items = parse_original_markdown(node)
      scratch[:original_tasklist_items] = original_items.compact
      scratch[:original_tasklist_title] = original_title

      # transform the inner contents of the task list from markdown to HTML
      inner_html_result = GitHub::Goomba::TasklistBlockContentPipeline.call(node.text_content, context)
      title, title_html = inner_html_result[:title], inner_html_result[:title_html]

      # set the tasklist block into the result object keyed by position. The position gets set on tasklist block items
      # in TasklistBlockItemFilter, and then used to find the tasklist block for each detected tasklist block item in
      # Async::TasklistBlockItemFilter.
      result[:tasklist_blocks] ||= {}
      result[:tasklist_blocks][@counter] = TasklistBlocks::TasklistBlock.new(
        name: title,
        name_html: title_html,
      )

      # check for sync errors
      if item.try(:hierarchy_synced?) == false
        validation_msg = "sync_error"
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:sync_error", "level:error"])
      end

      # Display error banner for existing tasklist blocks that have errors but are not being actively edited
      if has_existing_validation_error?
        validation_msg = "invalid_format"
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:existing_invalid_format", "level:error"])
      end

      # Check for limit errors
      number_of_tasks = original_title ? original_items.count - 1 : original_items.count
      number_of_tasklists = result[:tasklist_blocks].count
      msg, err = @limiter.check_if_exceed_limit(number_of_tasks, number_of_tasklists)
      result[:tasklist_block_errors] << err if err
      validation_msg = msg if msg

      completion = item.try(:hierarchy).try(:completion)

      view_component = component_class.new(
        # Since we no longer call issues-graph from the pipeline, we don't have access to the uuid.
        # Using the counter to have tasklist position as the unique identifier.
        id: @counter,
        title: original_title,
        title_html: title_html,
        readonly: item.nil?,
        items: nil,
        validation_msg: validation_msg,
        hierarchy_completion: completion,
        hierarchy_query_type: "",
        hierarchy_response_source_type: "",
        render_context: TrackingBlocks::RenderContextBlock.new(
          current_owner_login: repository.owner_display_login,
          current_repository_name: repository.name,
          current_repository_owner: repository.owner,
          current_item_display_number: item&.number,
        ),
        repository: repository,
        parent_issue: item,
        options: {
          tasklist_block_markdown_at_rest_enabled: true,
          tasklist_block_hard_limits_enabled: @tasklist_block_hard_limits_enabled
        }
      )

      @counter += 1
      # set the content of the tracking block to the transformed inner markdown content
      inner_html = GitHub::HTML::Result.to_html(inner_html_result)
      ApplicationController.render(view_component.with_content(inner_html), formats: [:html], layout: false)
    end

    def parse_original_markdown(node)
      item_prefix_type = T.let(nil, T.nilable(String))
      original_title = T.let(nil, T.nilable(String))

      markdown = node.text_content
      original_items = markdown.each_line.with_index.collect do |line, index|
        if index == 0 && matches = line.match(TASKLIST_TITLE_SELECTOR)
          # Tasklist block title
          original_title = matches[2]
          nil
        elsif matches = line.match(TaskList::Filter::TrackedIssuePatternParser)
          # Tasklist block item
          item_prefix = T.must(matches[0])[0]
          content = matches[2]

          # Validation
          check_if_nested_item(item_prefix, index)
          check_if_mismatched_prefix(item_prefix_type, item_prefix, index)
          check_if_empty_item(content, index)

          item_prefix_type ||= item_prefix
          content
        else
          invalid_item_error(line, index)
          line
        end
      end

      [original_title, original_items]
    end

    sig { returns(T::Boolean) }
    def has_existing_validation_error?
      is_currently_saving = context[:subject].try(:saved_changes?)
      has_errors = result[:tasklist_block_errors].any?

      @tasklist_block_validation_enabled &&
        !is_currently_saving &&
        has_errors
    end

    sig do
      params(prefix: String, index: Integer)
        .returns(T.nilable(T::Array[TasklistBlocks::ValidationError]))
    end
    def check_if_nested_item(prefix, index)
      return if prefix.present?
      GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:nested_item", "level:error"])
      result[:tasklist_block_errors] << TasklistBlocks::ValidationError.new(@counter, index, "nested item")
    end

    sig do
      params(prefix_type: T.nilable(String), prefix: String, index: Integer)
        .returns(T.nilable(T::Array[TasklistBlocks::ValidationError]))
    end
    def check_if_mismatched_prefix(prefix_type, prefix, index)
      return if prefix_type.nil?
      return if prefix.blank?
      return if prefix == prefix_type
      GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:mismatched_prefix", "level:error"])
      result[:tasklist_block_errors] << TasklistBlocks::ValidationError.new(@counter, index, "mismatched prefix")
    end

    sig do
      params(content: String, index: Integer)
        .returns(T.nilable(T::Array[TasklistBlocks::ValidationError]))
    end
    def check_if_empty_item(content, index)
      return if content.present?
      GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:empty_item", "level:error"])
      result[:tasklist_block_errors] << TasklistBlocks::ValidationError.new(@counter, index, "empty item")
    end

    sig { params(line: String, index: Integer).returns(T::Boolean) }
    def is_empty_line(line, index)
      return false if line.present?
      GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:empty_line", "level:error"])
      result[:tasklist_block_errors] << TasklistBlocks::ValidationError.new(@counter, index, "empty line")
      true
    end

    sig do
      params(line: String, index: Integer)
        .returns(T.nilable(T::Array[TasklistBlocks::ValidationError]))
    end
    def invalid_item_error(line, index)
      return if is_empty_line(line, index)
      # Generic invalid tasklist block item/content
      GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_item"])
      result[:tasklist_block_errors] << TasklistBlocks::ValidationError.new(@counter, index, "invalid item")
    end

    # Private: emit event for rendering a tasklist block, for publishing Hydro
    # events.
    #
    # Returns nothing.
    def instrument_tasklist_block_render
      return unless context[:subject]&.id
      GlobalInstrumenter.instrument("tasklist.render", {
        viewer: context[:current_user],
        issue_repository: context[:entity],
        issue: context[:subject],
        item_count: scratch[:original_tasklist_items].size,
        render_target: render_target,
      })
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

    sig { returns(Symbol) }
    def render_target
      if context[:render_mobile_tasklist_blocks]
        :MOBILE
      else
        :WEB
      end
    end
  end
end
