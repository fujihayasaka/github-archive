# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class TasklistBlockFilter < IssueMentionFilter
    extend T::Sig
    include ActionView::Helpers::OutputSafetyHelper

    # Processing tasklist blocks needs to be done for each tasklist block present in the generated HTML requiring us
    # to select on each list type. Work on the containing <li>'s will be done within #call
    TITLE_SELECTORS = "h1:-goomba-first-child-node, h2:-goomba-first-child-node, h3:-goomba-first-child-node, h4:-goomba-first-child-node, h5:-goomba-first-child-node, h6:-goomba-first-child-node"
    SELECTOR = Goomba::Selector.new(match: "#{TITLE_SELECTORS}, ol, ul", reject: "li > ul, li > ol")
    ISSUE_MENTION_ATTRIBUTE_SELECTOR = Goomba::Selector.new(match: "a[gh|issue-mention]")
    ISSUE_MENTION_ELEMENT_SELECTOR = Goomba::Selector.new(match: "gh|issue-mention")
    ISSUE_MENTIONS_SELECTOR = Goomba::Selector.new(match: "li > a[gh|issue-mention], li > gh|issue-mention")

    sig { returns(T::Array[Symbol]) }
    def self.feature_flags
      [:tasklist_block_nested_html_pipeline, :tasklist_block_precache, :tasklist_block_input_validation]
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.enabled?(context)
      # enable the filter only when authorization checks are safe to run
      return false unless safe_authorization_checks?(context)

      repository = context[:entity]

      return false unless repository.is_a?(Repository)

      # Are we rendering a persisted issue or a preview of a new issue?
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"
      return false if GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
      GitHub.flipper[:tasklist_block_nested_html_pipeline].enabled?(repository.owner)
    end

    def initialize(*args)
      super
      result[:tasklist_blocks] ||= []
      @original_tasklist_items = context.fetch(:original_tasklist_items, [])
      @original_tasklist_title = context.fetch(:original_tasklist_title, [])
      @name = "Tasks"
      @name_html = nil
      @items = []

      # For tasklist block validation
      @tasklist_block_validation_enabled = GitHub.flipper[:tasklist_block_input_validation].enabled?(context[:entity].owner)
      @issues = {}
      @has_validation_error = T.let(false, T.nilable(T::Boolean))
    end

    sig { returns(Goomba::Selector) }
    def selector
      SELECTOR
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
    def self.cache_key(context)
      return unless context[:viewer].present? && context[:cap_filter].present?
      "tasklist_block_calculate_readable_references"
    end

    sig { returns(T::Array[Promise[T.untyped]]) }
    def async_scan_nodes
      references = @nodes.flat_map do |list_node|
        list_node.select(ISSUE_MENTIONS_SELECTOR).to_a
      end.uniq

      references.map do |node|
        if node =~ ISSUE_MENTION_ATTRIBUTE_SELECTOR
          data = JSON.parse(node["gh:issue-mention"])
          nwo, number = data["nwo"], data["number"]
        else
          nwo, number = node["nwo"], node["number"]
        end

        async_issue_or_discussion_reference(number.to_i, nwo).then do |reference|
          next unless reference

          promises = [reference.async_repo_and_owner]

          if reference.respond_to?(:async_pull_request)
            promises << reference.async_pull_request
          end

          Promise.all(promises)
        end
      end
    end

    # call is expected to get called multiple times, once for the first heading, and then once for each list element
    # This sets up the state for the finished method to summarize the block and append to results
    sig { params(node: Goomba::ElementNode).returns(Goomba::ElementNode) }
    def call(node)
      @items = detect_tasklist_block_items(node) if [:ul, :ol].include?(node.tag)
      if [:h1, :h2, :h3, :h4, :h5, :h6].include?(node.tag)
        @name = @original_tasklist_title || node.text_content

        processed_array = node.children.map do |child|
          next child.text_content unless child.is_a?(Goomba::ElementNode)

          safe_html_if_sanitized(child.to_html)
        end

        # Use the ruby helper to escape any potential unsafe html in text nodes that haven't explicitly been
        # marked as html_safe
        @name_html = safe_join(processed_array, "")
      end

      node
    end

    # Takes the state as parsed by #call and summarizes the block and appends to results
    # If #call was never called, then this will insert an empty block with a default title
    sig { returns(T::Array[TasklistBlocks::TasklistBlock]) }
    def finished
      tasklist_block = if @has_validation_error
        TasklistBlocks::TasklistBlock.new(validation_msg: "invalid_items")
      else
        TasklistBlocks::TasklistBlock.new(name: @name, name_html: @name_html, items: @items)
      end
      result[:tasklist_blocks] << tasklist_block
    end

    private

    sig { params(node: Goomba::ElementNode).returns(T::Array[T.any(TasklistBlocks::IssueReference, TrackingBlocks::DraftIssue)]) }
    def detect_tasklist_block_items(node)
      # Only iterate over direct children of the list element. Any sub-<ol|ul> lists should be ignored.
      direct_tasklist_block_items = node.children.select do |child|
        is_element_node?(child) && child.tag == :li
      end

      tasklist_block_items = direct_tasklist_block_items.collect.with_index do |child, index|
        detect_tasklist_block_item(child, index)
      end

      tasklist_block_items.compact
    end

    # Private: Locates the issue reference element or returns the draft issue text.
    #
    # When the context provided to TasklistBlockFilter includes the original lines parsed by TasklistBlockPreFilter
    # the original user supplied Markdown is returned.
    #
    # node  - The Goomba::ElementNode <li> element.
    # index - Integer of the current list item index used to lookup the original draft issue Markdown.
    #
    # Returns Goomba::ElementNode or String
    sig { params(node: Goomba::ElementNode, index: Integer).returns(T.nilable(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference))) }
    def detect_tasklist_block_item(node, index)

      single_reference = get_single_reference(node)

      if single_reference
        load_issue_mention(single_reference)
      elsif repository.present?
        call_draft_issue(node, index, repository.owner_id)
      end
    end

    sig { params(node: Goomba::ElementNode).returns(T.nilable(Goomba::ElementNode)) }
    private def get_single_reference(node)
      issue_mentions = node.children.select do |child|
        is_element_node?(child) && (child =~ ISSUE_MENTION_ELEMENT_SELECTOR || child =~ ISSUE_MENTION_ATTRIBUTE_SELECTOR)
      end

      return nil unless issue_mentions.count == 1

      checkbox_md = node.children.select do |child|
        is_text_node?(child) && child.inner_html != "\n"
      end

      return nil unless checkbox_md.count == 1 && checkbox_md.first.inner_html.match?(/#{TaskList::Filter::ItemPatternParser}\s*$/)

      reference = issue_mentions.first

      # The text content of the issue mention element should match the href attribute. If it does not, this means that the issue url is being used in a markdown link and should be treated as a draft issue.
      if reference["href"] && reference["href"] != reference.text_content
        reference.remove_attribute("gh:issue-mention")
        reference.remove_attribute("gh:discussion-mention")

        return nil
      end

      reference
    end

    sig { params(node: Goomba::ElementNode).returns(T.nilable(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference))) }
    def load_issue_mention(node)
      # Does the element match the a[gh:issue-mention] selector?
      if node =~ ISSUE_MENTION_ATTRIBUTE_SELECTOR
        call_a(node)
      # Does the element match the <gh:issue-mention> element?
      elsif node =~ ISSUE_MENTION_ELEMENT_SELECTOR
        call_gh(node)
      end
    end

    # Private: Extract a draft issue title and closed state from a given list item node.
    #
    # node  - The Goomba::ElementNode <li> element.
    # index - Integer of the current list item index used to lookup the original draft issue Markdown.
    #
    # Returns TrackingBlocks::DraftIssue
    sig { params(node: Goomba::ElementNode, index: Integer, owner_id: Integer).returns(T.nilable(TrackingBlocks::DraftIssue)) }
    def call_draft_issue(node, index, owner_id)
      draft_issue_md = @original_tasklist_items[index]
      # If the original line was not parsed for any reason, as a fallback we'll grab the text of each node
      # Will also parse for completion here
      text_content = node.text_content.squish
      match_results = text_content.scan(TaskList::Filter::TrackedIssuePatternParser)

      # Return if draft title is empty (ex. "- [ ]")
      return unless match_results.length > 0

      match_results.each do
        draft_issue = draft_issue_md&.squish || $2
        # Limit draft length to 512 characters
        if @tasklist_block_validation_enabled && draft_issue.length > 512
          @has_validation_error = true
          GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_length", "level:error"])
          return
        end

        closed = closed($1)
        html_string_array = process_node_children(node)

        # If draft title contains any markdown, process into an html string
        return TrackingBlocks::DraftIssue.new(
          draft_issue: draft_issue,
          owner_id: owner_id,
          closed: closed,
          title_html: html_string_array
        )
      end
    end

    # Private: Process the various cases of a markdown formatted draft issue
    #
    # Returns String
    sig { params(node: Goomba::ElementNode).returns(T.nilable(String)) }
    def process_node_children(node)
      return unless node.children.length > 1

      processed_array = node.children.map.with_index do |child, index|
        if index.zero?
          # if item starts with plain text, (ex. "- [ ] plain text"), remove checkbox and add text to results
          match_results = child.text_content.scan(/\A#{TaskList::Filter::ItemPatternParser}?\s*(.*)/)
          next match_results[0][1] if match_results.length > 0
        elsif child.respond_to?(:remove_attribute)
          # remove any hovercard attributes from the issue mention node
          child.remove_attribute("data-hovercard-type")
          child.remove_attribute("data-hovercard-url")
        end

        next child.text_content unless child.is_a?(Goomba::ElementNode)

        safe_html_if_sanitized(child.to_html)
      end

      # Use the ruby helper to escape any potential unsafe html in text nodes that haven't explicitly been
      # marked as html_safe
      safe_join(processed_array, "")
    end

    # Private: Return if checkbox markdown indicates completion.
    #
    # checkbox - text in the format `[ ]` or `[x]`
    #
    # Returns Boolean
    sig { params(checkbox: String).returns(T::Boolean) }
    def closed(checkbox)
      !!(checkbox =~ TaskList::Filter::CompletePattern)
    end

    # Private: Check if issue reference already exists in the current tasklist block, set validation error if so.
    #
    # issue_ref - the issue reference object
    #
    # Returns TasklistBlocks::IssueReference
    sig { params(issue_ref: TasklistBlocks::IssueReference).returns(TasklistBlocks::IssueReference) }
    def check_if_duplicate_issue(issue_ref)
      if @tasklist_block_validation_enabled && @issues["#{issue_ref.issue.repository_id}/#{issue_ref.issue.id}"]
        @has_validation_error = true
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_duplicate", "level:error"])
      end
      @issues["#{issue_ref.issue.repository_id}/#{issue_ref.issue.id}"] = true
      issue_ref
    end

    # Any issue referenced by number (#1) or shorthand (github/repo#1) within tasklist blocks need to be parsed and
    # load the referenced issue to be tracked within the current tasklist block.
    #
    # See call_a for all issue references by URL (https://github.com/github/github/issues/1)
    #
    # node - The Goomba::ElementNode <gh:issue-mention> element.
    #
    # Returns an IssueReference or a DraftIssue.
    sig { params(node: Goomba::ElementNode).returns(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference)) }
    def call_gh(node)
      nwo, marker, number = node["nwo"], node["marker"], node["number"]
      reference = issue_reference(nwo, number)
      if reference.blank? || (calculate_readable_references? && !reference.readable?)
        TrackingBlocks::DraftIssue.new(
          draft_issue: [nwo, marker, number].compact.join,
          owner_id: repository.owner_id,
        )
      else
        check_if_duplicate_issue(TasklistBlocks::IssueReference.new(issue: reference.issue))
      end
    end

    # Any issue referenced by URL within tasklist blocks need to be parsed and load the referenced issue to be tracked
    # within the current tasklist block.
    #
    # See call_gh for all issue references by number (#1) or shorthand (github/repo#1)
    # Returns a DraftIssue or an IssueReference.
    sig { params(node: Goomba::ElementNode).returns(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference)) }
    def call_a(node)
      href, inner_html = node["href"], node.inner_html
      data = JSON.parse(node["gh:issue-mention"])
      nwo, number, anchor = data["nwo"], data["number"], data["anchor"]
      reference = issue_reference(nwo, number)

      # TODO: Determine if we want to ignore inner_html and add reference to tasklist block anyways
      # The tasklist item markdown needs to be exclusively a URL:
      # - [ ] https://github.com/github/github/issues/1
      # Not:
      # - [ ] [My issue](https://github.com/github/github/issues/1)
      if href != inner_html || reference.blank? || (calculate_readable_references? && !reference.readable?)
        TrackingBlocks::DraftIssue.new(
          draft_issue: inner_html,
          owner_id: repository.owner_id,
        )
      else
        check_if_duplicate_issue(TasklistBlocks::IssueReference.new(issue: reference.issue))
      end
    end
  end
end
