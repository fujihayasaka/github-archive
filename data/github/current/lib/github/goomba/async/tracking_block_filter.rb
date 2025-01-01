# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class TrackingBlockFilter < IssueMentionFilter
    # Processing tracking blocks needs to be done for each tracking block present in the generated HTML requiring us
    # to select on each list type. Work on the containing <li>'s will be done within #call
    SELECTOR = Goomba::Selector.new(match: "tracking-block")
    ISSUE_ATTR_SELECTOR = Goomba::Selector.new(match: "a[gh|issue-mention]")
    URL_SELECTOR = Goomba::Selector.new(match: "a[href]")
    ISSUE_MENTIONS_SELECTOR = Goomba::Selector.new(match: "li > a[gh|issue-mention], li > gh|issue-mention")

    def self.feature_flags
      [:tasklist_block, :tasklist_block_nested_html_pipeline, :tasklist_block_precache]
    end

    def self.enabled?(context)
      return false if context[:disable_issues_graph] == true
      # enable the filter only when authorization checks are safe to run
      return false unless safe_authorization_checks?(context)

      repository = context[:entity]

      return false unless repository.is_a?(Repository)
      return false unless context[:subject].is_a?(Issue)

      return false if GitHub.flipper[:tasklist_block_precache].enabled?(repository.owner)
      # If a repository has the nested HTML pipeline enabled, issue references and draft issues are detected with the
      # `GitHub::Goomba::Async::TasklistBlockFilter` within the `GitHub::Goomba::TasklistBlockPipeline`.
      return false if GitHub::Goomba::Async::TasklistBlockFilter.enabled?(context)

      GitHub.flipper[:tasklist_block].enabled?(repository.owner)
    end

    # Public: The current tracking block array that contains each issue, pull request, or draft issue.
    #
    # Examples
    #
    #   @tracking_items # => [TrackingBlocks::DraftIssue, TrackingBlocks::Issue]
    #
    # Returns Array of issue URLs or draft issues.
    attr_reader :tracking_items

    def initialize(*args)
      super
      @tracking_items = []
      result[:tracking_blocks] ||= []
    end

    def selector
      SELECTOR
    end

    def self.cache_key(context)
      return unless context[:viewer].present? && context[:cap_filter].present?
      "calculate_readable_references"
    end

    def async_scan_nodes
      # Find all issue mentions within tracking-block elements to prefill the cache with GitHub::HTML::IssueReference
      # that can be used to prepare tracking blocks for calculating the Hierarchy within github/issues-graph
      references = @nodes.flat_map do |list_node|
        list_node.select(ISSUE_MENTIONS_SELECTOR).to_a
      end.uniq

      references.map do |node|
        if node =~ ISSUE_ATTR_SELECTOR
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

    def calculate_readable_references?
      context[:viewer].present? && context[:cap_filter].present?
    end

    # call is called for each <tracking-block> list and are processed independently.
    def call(node)
      name = T.let("Tasks", T.untyped)

      node.children.each do |list|
        next unless is_element_node?(list)
        if list.tag == :ol || list.tag == :ul
          list.children.each do |list_item|
            # First, attempt to parse the happy path format of a tracking block item
            tracking_item, is_checked = detect_tracking_item(list_item)
            if tracking_item
              if is_text_node?(tracking_item)
                next call_draft(tracking_item.text_content.squish, is_checked)
              elsif is_element_node?(tracking_item)
                # Does the element match the a[gh:issue-mention] selector?
                if tracking_item =~ ISSUE_ATTR_SELECTOR
                  next call_a(tracking_item)
                elsif tracking_item =~ URL_SELECTOR
                  next call_draft(tracking_item["href"], is_checked)
                else
                  next call_gh(tracking_item)
                end
              end
            end

            # Failing the happy path, make an effort to derive a draft issue
            call_draft_fallback(list_item)
          end
        elsif [:h1, :h2, :h3, :h4, :h5, :h6].include?(list.tag)
          name = list.text_content.squish
        end
      end

      result[:tracking_blocks] << TasklistBlocks::TasklistBlock.new(
        name: name,
        items: tracking_items
      )

      node
    ensure
      @tracking_items = []
    end

    private

    def detect_tracking_item(node)
      # There can only be two elements in a tracking block item, the first element is a input[type=checkbox], and the
      # second can be either a <gh:issue-mention>, <a>, or text node.
      #
      # The two element requirement prevents the following markup from being valid:
      #
      # <li>
      #   <input type="checkbox">
      #   <gh:issue-mention nwo="monalisa/smile" marker="#" number="2"></gh:issue-mention>
      #   Additional text
      # </li>
      return unless is_element_node?(node)

      # Strip out any whitespace characters in between input and elements
      nodes = node.children.reject do |el|
        is_text_node?(el) && el.inner_html.squish.blank?
      end
      return unless nodes.length == 2

      checkbox = nodes.first
      return unless is_checkbox_node?(checkbox)

      [nodes.second, checkbox["checked"] != nil]
    end

    def is_checkbox_node?(node)
      # Depending on the filters present in the pipeline, the checkbox may be text or an input[type=checkbox]
      if is_element_node?(node)
        true if node.tag == :input && node["type"] == "checkbox"
      elsif is_text_node?(node)
        true if node.inner_html.match?(/#{TaskList::Filter::ItemPatternParser}\s*\z/)
      end
    end

    # Any issue referenced by number (#1) or shorthand (github/repo#1) within tracking blocks need to be parsed and
    # load the referenced issue to be tracked within the current tracking block.
    #
    # See call_a for all issue references by URL (https://github.com/github/github/issues/1)
    def call_gh(node)
      nwo, marker, number = node["nwo"], node["marker"], node["number"]

      reference = issue_reference(nwo, number)
      if reference.nil? || calculate_readable_references? && !reference.readable?
        return call_draft("#{nwo}#{marker}#{number}")
      end

      tracking_items << TasklistBlocks::IssueReference.new(issue: reference.issue)
    end

    # Any issue referenced by URL within tracking blocks need to be parsed and load the referenced issue to be tracked
    # within the current tracking block.
    #
    # See call_gh for all issue references by number (#1) or shorthand (github/repo#1)
    def call_a(node)
      href, inner_html = node["href"], node.inner_html
      data = JSON.parse(node["gh:issue-mention"])
      nwo, number, anchor = data["nwo"], data["number"], data["anchor"]
      reference = issue_reference(nwo, number)

      # TODO: Determine if we want to ignore inner_html and add reference to tracking block anyways
      # The tracking item markdown needs to be exclusively a URL:
      # - [ ] https://github.com/github/github/issues/1
      # Not:
      # - [ ] [My issue](https://github.com/github/github/issues/1)
      if reference.nil? || calculate_readable_references? && !reference.readable? || href != inner_html
        return call_draft(href)
      end

      tracking_items << TasklistBlocks::IssueReference.new(issue: reference.issue)
    end

    def call_draft(draft_issue, closed = false)
      # we can only create draft issues if we have a repository to "store" them under
      tracking_items << TrackingBlocks::DraftIssue.new(
        draft_issue: draft_issue,
        owner_id: context[:entity].owner_id,
        closed: closed,
      ) if context[:entity].is_a?(Repository)
    end

    def call_draft_fallback(list_item)
      # Bail, if this isn't a list element with children
      return unless is_element_node?(list_item) &&
        list_item.tag == :li &&
        list_item.children.any?

      closed = T.let(false, T::Boolean)
      content = list_item.children.collect do |node|
        # Grab open/close state from checkbox, if we find one
        if is_checkbox_node?(node)
          closed = node["checked"] != nil
          next
        end

        if is_element_node?(node)
          # HACK: try to detect and re-furl links with gh:issue-mention attribute
          if node.tag == :a && node.attributes.include?("gh:issue-mention")
            next node.text_content
          end

          # HACK: try to detect and re-furl <gh:issue-mention> element
          if node.attributes.include?("marker")
            refurled_gh_mention = "#{node["nwo"]}#{node["marker"]}#{node["number"]}"
            if refurled_gh_mention =~ GitHub::HTML::IssueMentionFilter::MARKER
              next refurled_gh_mention
            end
          end
        end

        # Try to render everything else back out to HTML
        node.to_html
      end.join("").squish

      call_draft(content, closed)
    end
  end
end
