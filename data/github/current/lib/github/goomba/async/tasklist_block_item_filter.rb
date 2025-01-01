# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  # Goomba node filter that transforms a list item with a `gh:tracking-block-item`
  # attribute into a rendered TrackingBlocks:TasklistBlockItemComponent component.
  #
  # This filter doesn't scan the HTML document itself, but it relies on the scan done by
  # Async::IssueMentionFilter to find issue references in order to determine if each
  # tracking block list item should be rendered as a draft or not.
  class TasklistBlockItemFilter < NodeFilter
    extend T::Sig
    include ActionView::Helpers::OutputSafetyHelper

    SELECTOR = Goomba::Selector.new(match: "li[gh|tracking-block-item]", reject: "li[hidden]")

    def initialize(*args)
      super
      # For tasklist block validation
      @tasklist_block_validation_enabled = GitHub.flipper[:tasklist_block_input_validation].enabled?(context[:entity].owner)
      @current_tasklist_id = nil
      @current_item_id = nil
      @issues = {}
      @validation_error = T.let(nil, T.nilable(String))
    end

    def async_scan
      Promise.resolve
    end

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      hierarchy = context[:subject].try(:hierarchy)
      hierarchy&.issue&.timestamp
    end

    sig { returns(T::Array[Symbol]) }
    def self.feature_flags
      [:tasklist_block_precache]
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.enabled?(context)
      return false unless context[:entity].is_a?(Repository)
      # As we do not support cross-references yet, we do not need to unfurl the
      # tracking block if the subject is not a persisted issue. Issue
      # comment previews will have a subject_type populated, but not subject.
      return false unless context[:subject].is_a?(Issue) || context[:subject_type] == "Issue"
      GitHub.flipper[:tasklist_block_precache].enabled?(context[:entity].owner)
    end

    def call(node)
      repository = context[:entity]

      # get parent tasklist
      tasklist, id = tasklist_for_node(node)
      @current_tasklist_id = id

      content = process_node_children(node)

      tasklist_item = detect_tasklist_block_item(node)
      is_item_template = node.select("div.empty-template-title").any?

      # if node is an empty template for optimistic updates, return it
      return node if is_item_template
      # if no tasklist item detected, don't render anything
      return false if !tasklist_item

      # add the detected tasklist item to the parent tasklist if one exists
      if tasklist
        tasklist.items << tasklist_item

        # get metadata from preloaded hierarchy
        item_index = tasklist.items.length - 1
        @current_item_id = item_index
        assignees, labels, completion = metadata_for_tasklist_item(id, item_index)
      end

      component = component_class.new(
        **tasklist_item.to_tasklist_issue.to_h,
        readonly: context[:subject].nil?,
        tasklist_block_id: @current_tasklist_id,
        uuid: @current_item_id,
        assignees: assignees || [],
        labels: labels || [],
        completion: completion&.to_h,
        repository: repository,
        parent_issue: context[:subject],
        error: @validation_error,
        render_context: TrackingBlocks::RenderContextItem.new(
          current_owner_login: repository.owner_display_login,
          current_repository_name: repository.name,
          current_repository_owner: repository.owner
        )
      )
      @validation_error = nil

      ApplicationController.render(
        component.with_content(content),
        formats: [:html],
        layout: false
      )
    end

    private

    def metadata_for_tasklist_item(tasklist_id, item_id)
      hierarchy = context[:subject].try(:hierarchy)
      tasklist_blocks = hierarchy&.tasklist_blocks
      return unless tasklist_blocks&.any?

      tasklist_block = tasklist_blocks[tasklist_id.to_i]
      return unless items = tasklist_block&.items
      return unless issue = items[item_id.to_i]

      [issue.assignees, issue.labels, issue.completion]
    end

    def tasklist_for_node(node)
      return if result[:tasklist_blocks].empty?

      tracking_block_node = find_node_ancestor(node, "tracking-block")
      return unless tracking_block_node

      id = tracking_block_node["data-id"]
      return unless id

      [result[:tasklist_blocks][id.to_i], id]
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
    sig { params(node: Goomba::ElementNode).returns(T.nilable(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference))) }
    def detect_tasklist_block_item(node)
      issue_mentions = node
        .select("#{IssueMentionFilter::ISSUE_ELEM_SELECTOR.match_selector}, #{IssueMentionFilter::ISSUE_ATTR_SELECTOR.match_selector}")
        .to_a
      children_with_content = node.children.select do |child|
        next false if child.matches("input[type='checkbox']")
        next false if child.is_a?(Goomba::TextNode) && child.text_content.squish.blank?

        true
      end

      single_reference = children_with_content.count == 1 && issue_mentions.count == 1
      if single_reference
        load_issue_mention(issue_mentions.first)
      elsif repository.present?
        call_draft_issue(node, repository.owner_id)
      end
    end

    sig { params(node: Goomba::ElementNode).returns(T.nilable(T.any(TrackingBlocks::DraftIssue, TasklistBlocks::IssueReference))) }
    def load_issue_mention(node)
      # Does the element match the a[gh:issue-mention] selector?
      if node =~ IssueMentionFilter::ISSUE_ATTR_SELECTOR
        call_a(node)
      # Does the element match the <gh:issue-mention> element?
      elsif node =~ IssueMentionFilter::ISSUE_ELEM_SELECTOR
        call_gh(node)
      end
    end

    # Private: Extract a draft issue title and closed state from a given list item node.
    #
    # node  - The Goomba::ElementNode <li> element.
    # index - Integer of the current list item index used to lookup the original draft issue Markdown.
    #
    # Returns TrackingBlocks::DraftIssue
    sig { params(node: Goomba::ElementNode, owner_id: Integer).returns(T.nilable(TrackingBlocks::DraftIssue)) }
    def call_draft_issue(node, owner_id)
      draft_issue_md = node["gh:tracking-block-item"]
      # If the original line was not parsed for any reason, as a fallback we'll grab the text of each node
      # Will also parse for completion here
      text_content = node.text_content.squish
      checkbox = node.children.find { |n| n.matches("input[type='checkbox']") }

      # Return if draft title is empty (ex. "- [ ]") or a checkbox is not found
      return if checkbox.nil? || text_content.blank?

      draft_issue = draft_issue_md&.squish || text_content

      if @tasklist_block_validation_enabled && draft_issue.length > 512
        @validation_error = "invalid_length"
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_length", "level:error"])
      end

      closed = checkbox.attributes.has_key?("checked")
      html_string_array = process_node_children(node)

      # If draft title contains any markdown, process into an html string
      TrackingBlocks::DraftIssue.new(
        draft_issue: draft_issue,
        owner_id: owner_id,
        closed: closed,
        title_html: html_string_array
      )
    end

    # Private: Process the various cases of a markdown formatted draft issue
    #
    # Returns String
    sig { params(node: Goomba::ElementNode).returns(T.nilable(String)) }
    def process_node_children(node)
      processed_array = node.children.filter_map.with_index do |child, index|
        next if index.zero? && child.matches("input[type='checkbox']")

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
      issue_key = "#{@current_tasklist_id}/#{issue_ref.issue.repository_id}/#{issue_ref.issue.id}"
      if @tasklist_block_validation_enabled && @issues[issue_key]
        @validation_error = "invalid_duplicate"
        GitHub.dogstats.increment(TasklistBlocks::TasklistBlock::TASKLIST_BLOCK_VALIDATION, tags: ["type:invalid_duplicate", "level:error"])
      end
      @issues[issue_key] = true
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
      if reference.blank?
        TrackingBlocks::DraftIssue.new(
          draft_issue: [nwo, marker, number].compact.join,
          owner_id: repository.owner_id
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
      nwo, number = data["nwo"], data["number"]
      reference = issue_reference(nwo, number)

      # TODO: Determine if we want to ignore inner_html and add reference to tasklist block anyways
      # The tasklist item markdown needs to be exclusively a URL:
      # - [ ] https://github.com/github/github/issues/1
      # Not:
      # - [ ] [My issue](https://github.com/github/github/issues/1)
      if href != inner_html || reference.blank?
        TrackingBlocks::DraftIssue.new(
          draft_issue: "#{nwo}##{number}",
          owner_id: repository.owner_id
        )
      else
        check_if_duplicate_issue(TasklistBlocks::IssueReference.new(issue: reference.issue))
      end
    end

    # Issues references are pre-fetched by the GithubReferenceFilter in the scan step, so when this filter is called
    # we already have data from MySQL for each issue.
    #
    # Returns an IssueReference if one exists, otherwise nil.
    sig { params(owner_or_nwo: T.nilable(String), number: T.any(String, Integer)).returns(T.nilable(GitHub::HTML::IssueReference)) }
    def issue_reference(owner_or_nwo, number)
      return nil if scratch[:issue_references].blank?

      key = [owner_or_nwo, number.to_i]
      scratch[:issue_references][key]
    end

    sig do
      returns(
        T.any(
          T.class_of(TrackingBlocks::TasklistBlockItemComponent),
          T.class_of(TrackingBlocks::TasklistBlockMobileItemComponent),
        )
      )
    end
    def component_class
      if context[:render_mobile_tasklist_blocks]
        TrackingBlocks::TasklistBlockMobileItemComponent
      else
        TrackingBlocks::TasklistBlockItemComponent
      end
    end
  end
end
