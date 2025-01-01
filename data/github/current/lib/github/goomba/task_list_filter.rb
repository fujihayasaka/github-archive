# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Adds the "contains-task-list" class to list elements that contain task list items,
  # and the "task-list-item" class to list item elements that are task list
  # items. Replaces task list item markers (`[ ]` and `[x]`) with checkboxes.
  #
  # Syntax
  # ------
  #
  # Task list items must be in a list format:
  #
  # ```
  # - [ ] incomplete
  # - [x] complete
  # ```
  #
  # Results
  # -------
  #
  # The following keys are written to the result hash:
  #   :task_list_items - An array of TaskList::Item objects.
  #   :tracked_issue_anchors - An array of TaskList::TrackedIssueAnchor
  #   :tracked_alert_anchors - An array of AlertMentionFilter::Item
  class TaskListFilter < NodeFilter
    SELECTOR = Goomba::Selector.new([
      "ol",
      "ul",
      "li > :text:-goomba-first-child-node",
      "li > p:first-child > :text:-goomba-first-child-node",
    ].join(", "))

    def initialize(*args)
      super
      @filter = TaskList::Filter.new("", context, result)
    end

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:extract_checklists]
    end

    def self.cache_key(context)
      GitHub.task_list_cache_version
    end

    def call(node)
      if is_element_node?(node)
        call_list(node)
      else
        call_text(node)
      end
    end

    def finished
      result[:task_list_summary] = TaskList::Summary.new(Array(result[:task_list_items]))
    end

    protected

    # Remove this method and it's invocation when :extract_checklists feature flag is deleted
    def extract?
      entity.is_a?(Repository) && entity.extract_checklists_enabled?
    end

    def issues_alerts_integration_enabled?
      entity.is_a?(Repository) && entity.issues_alerts_integration_enabled?
    end

    def parse_nested_from_text(text)
      text.match(TaskList::Filter::TrackedIssuePatternParser) do |_match|
        if $2 && !$2.empty?
          anchor = TaskList::TrackedIssueAnchor.new($1, $2)
          @filter.tracked_issue_anchors << anchor
        end
      end
    end

    def parse_nested_from_node(li_element)
      # we need to check whether it has an <a> tag and parse it
      a = li_element.children.select { |el| is_element_node?(el) and el.tag == :a }
      checkbox_md = li_element.children.select { |el| is_text_node?(el) && el.inner_html != "\n" }

      # we do not extract nested issues in the following cases:
      #   <li>- [ ] <a href="https://...">https://...</a> some text</li>
      #   <li>- [ ] some text <a href="https://...">https://...</a></li>
      #   <li>- [ ] <a href="https://...">https://...</a> <a href="https://...">https://...</a></li>
      # we extract nested issue only if list item contains checkbox markdown and a single link:
      #   <li>- [ ] <a href="https://...">https://...</a></li>
      extract = a.count == 1 && checkbox_md.count == 1 && checkbox_md.first.inner_html =~ /#{TaskList::Filter::ItemPatternParser}\s*$/

      if extract
        href = a.first.attributes["href"]
        if href && !href.empty?
          checkbox = checkbox_md.first.inner_html.match(TaskList::Filter::ItemPatternParser)[1]
          anchor = TaskList::TrackedIssueAnchor.new(checkbox, href)
          @filter.tracked_issue_anchors << anchor

          if issues_alerts_integration_enabled? && m = href.match(AlertMentionFilter.security_alert_url_pattern)
            @filter.tracked_alert_anchors << AlertMentionFilter::Item.new(m, checkbox)
          end
        end
      end
    end

    def call_list(element)
      items = element.children.select { |child| task_list_item?(child) }
      return if items.empty?

      items.each do |item|
        add_class(item, "task-list-item")

        if extract?
          # every item is a <li> tag which has a checkbox [ ] inside
          # the text content is parsed in call_text method
          parse_nested_from_node(item)
        end
      end
      add_class(element, "contains-task-list")

      element
    end

    def call_text(text)
      if extract?
        parse_nested_from_text(text.html)
      end

      text.html.sub!(TaskList::Filter::ItemPatternParser) do |_match|
        item = TaskList::Item.new($1)
        @filter.task_list_items << item
        @filter.render_item_checkbox(item)
      end
    end

    def task_list_item?(element)
      return false unless is_element_node?(element)
      return false unless element.tag == :li
      first_child = element.children.first
      if is_text_node?(first_child) && first_child.inner_html == "\n"
        first_child = first_child.next_sibling
      end
      if is_element_node?(first_child) && first_child.tag == :p
        first_child = first_child.children.first
      end
      return false unless is_text_node?(first_child)

      !!(first_child.html =~ TaskList::Filter::ItemPatternParser)
    end

    def add_class(element, klass)
      element["class"] = [element["class"], klass].compact.join(" ")
    end
  end
end
