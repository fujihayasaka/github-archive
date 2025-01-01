# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # TasklistBlockPreFilter is responsible for populating the `tasklist_blocks` key in the pipeline result with any
  # tasklist block detected in the Markdown. Tasklist block items are detected by taking the raw Markdown contained
  # within the matching [tasklist] block codefence and running it through GitHub::Goomba::TasklistBlockPipeline.
  #
  # The result of the nested HTML pipeline is then used to render the tasklist block preview.
  #
  # When an issue is saved, all tasklist blocks present in the Markdown will be replaced with a
  # URL containing a reference to the tasklist block. To see how tasklist block URLs are expanded on show,
  # see GitHub::Goomba::TrackingBlockExpansionFilter.
  class TasklistBlockPreFilter < NodeFilter
    extend T::Sig

    # Pattern used for matching tasklist title
    TASKLIST_TITLE_SELECTOR = /(^#*) #{TaskList::Filter::IssueTextPattern}/

    SELECTOR = Goomba::Selector.new(match: "pre[lang='[tasklist]']")

    sig { returns(T::Array[Symbol]) }
    def self.feature_flags
      [:tasklist_block_nested_html_pipeline, :tasklist_block_precache, :tasklist_block_input_validation]
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.enabled?(context)
      return false if context[:disable_issues_graph] == true
      # enable the filter only when authorization checks are safe to run, or when previewing
      return false unless safe_authorization_checks?(context) || context[:previewing]

      repository = context[:entity]

      return false unless repository.is_a?(Repository)

      # Are we rendering a persisted issue or a preview of a new issue?
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"
      return false if GitHub.flipper[:tasklist_block_precache].enabled?(repository.owner)
      GitHub.flipper[:tasklist_block_nested_html_pipeline].enabled?(repository.owner)
    end

    sig { returns(Goomba::Selector) }
    def selector
      SELECTOR
    end

    def initialize(*args)
      super
      result[:tasklist_blocks] ||= []
      @tasklist_block_validation_enabled = GitHub.flipper[:tasklist_block_input_validation].enabled?(context[:entity].owner)
    end

    sig { params(element: Goomba::ElementNode).returns(Goomba::ElementNode) }
    def call(element)
      # Populate `tasklist_blocks` in the result class.
      tasklist_pipeline_result(element)
      element
    end

    private

    sig { returns(T.nilable(Issue)) }
    def issue
      context[:subject] if context[:subject].is_a?(Issue)
    end

    # Private: Call the nested HTML pipeline to parse the tasklist items and populate the `tasklist_blocks` key in
    # the result class.
    #
    # element - The <pre> Goomba::Element
    #
    # Returns GitHub::HTML::Result
    sig { params(element: Goomba::ElementNode).returns(T.any(GitHub::HTML::Result, T::Hash[Symbol, T.untyped], Goomba::ElementNode)) }
    def tasklist_pipeline_result(element)
      # The <pre> contains a text node as its child element
      # Strip leading whitespace for each line to handle nested items
      markdown = T.let(element.children.first.text_content.lines.map(&:strip).join("\n"), String)

      validation_error = T.let(nil, T.nilable(String))
      item_prefix_type = T.let("", T.nilable(String))
      # Capture the original Markdown supplied by the user to preserve Markdown formatting when rendering Tasklists
      original_title = T.let(nil, T.nilable(String))
      original_items = markdown.each_line.with_index.collect do |line, index|
        if index == 0 && matches = line.match(TASKLIST_TITLE_SELECTOR)
          original_title = matches[2]
        end
        if matches = line.match(TaskList::Filter::TrackedIssuePatternParser)
          # Ensure that all items in the tasklist block have the same prefix type
          item_prefix = T.must(matches[0])[0]
          prefix_matches = item_prefix_type.blank? || item_prefix == item_prefix_type
          unless !@tasklist_block_validation_enabled || prefix_matches
            validation_error = "invalid_format"
            GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_prefix", "level:error"])
            break
          end
          item_prefix_type = item_prefix

          matches[2]
        elsif @tasklist_block_validation_enabled
          unless index == 0 && line.match(/(\#{1,6}\s)/) # let title lines with correct formatting through
            # If it is not the title line and not a valid issue
            validation_error = "invalid_format"
            GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_format", "level:error"])
            break ## stop going through the rest of the tasklist block when we find an invalid case
          end
        end
      end

      if validation_error
        result[:tasklist_blocks] << TasklistBlocks::TasklistBlock.new(
          validation_msg: validation_error
        )
        return element
      end

      nested_context = context.merge(original_tasklist_items: original_items.compact, original_tasklist_title: original_title)
      GitHub::Goomba::TasklistBlockPipeline.call(markdown, nested_context, result)
    end
  end
end
