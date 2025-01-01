# typed: strict
# frozen_string_literal: true

module SubIssuesHelpers
  extend T::Helpers

  requires_ancestor { ActiveSupport::TestCase }

  # Creates a hierarchy of sub-issues based on a text/visual representation of the tree.
  #
  # ## Example
  # ```rb
  # create_hierarchy! <<~HIERARCHY
  # - parent
  #   - child1
  #   - child2
  #     - grandchild1
  # - parent2
  #    - child3
  # HIERARCHY
  # ```
  #
  # This would create issues with the names "parent", "child1", "child2", "grandchild1", "parent2", and "child3".
  # Then, it would add "child1" and "child2" as sub-issues of "parent", and "grandchild1" as a sub-issue of "child2"
  # by calling `add_sub_issue!` on the parent issues: `parent.add_sub_issue!(child1, user.id)`.
  #
  # ## Example with existing issues
  #
  # You can also create a hierarchy if you have already created issues (such as from a test fixture) by passing
  # a list of issues into `create_hierarchy!` and interpolating the issues directly into the hierarchy string.
  #
  # ```rb
  # issue1 = create(:issue)
  # issue2 = create(:issue)
  # issue3 = create(:issue)
  # create_hierarchy!("
  # - #{issue1}
  #   - #{issue2}
  #     - #{issue3}
  # ", issues: [issue1, issue2, issue3])
  # ```
  #
  # This would create a nested hierarchical structure, only creating the sub-issue relationships, but not creating any
  # new issues. Internally, this works by searching for the default string representation of the issue in the array,
  # such as a string like `#<Issue:0x00007f8a0a0a0a0a>`.
  sig { params(tree: String, issues: T.nilable(T::Array[Issue]), repository: T.nilable(::Repository)).returns(T::Hash[String, Issue]) }
  def create_hierarchy!(tree, issues: nil, repository: nil)
    scanner = StringScanner.new(tree)
    items = T.let({}, T::Hash[String, Issue])
    stack = T.let([], T::Array[Issue])
    current_indent = ""
    last_indent = ""
    repository ||= ::FactoryBot.create(:repository)

    until scanner.eos?
      case
      when scanner.scan("\n")
        last_indent = current_indent
        current_indent = ""
      when scanner.scan(/-/)
        scanner.skip(" ") # Skip over whitespace after the dash, not semantically important

        issue = T.let(
          # If it looks like a reference to an existing issue in memory, then we will try to find the
          # model in memory, which is a little bit hacky, but it works for tests.
          if scanner.match?("#<Issue")
            reference = scanner.scan_until(/>/)

            msg = <<~MSG
            \nExpected a list of issues to be passed to create_hierarchy!, but didn't get anything.

            To directly interpolate issues into the hierarchy, you need to pass the list of issues as an additional argument
            to create_hierarchy! like: `create_hierarchy!("...", issues: [issue1, issue2, issue3])`
            MSG
            raise msg unless issues

            referenced_issue = issues.find { |i| i.to_s == reference }
            raise "Expected to find an issue with the reference #{reference} in memory, but none was found. Did you ensure that all issues were passed to `create_hierarchy!`?" unless referenced_issue
            referenced_issue
          else
            # By default, the text in the rest of the line is the title of the issue.
            title = scanner.scan(/.+/)
            raise "Expected title text around #{scanner.pos} after hyphen: #{scanner.rest}" unless title

            ::FactoryBot.create(:issue, title:, repository:)
          end,
          Issue
        )

        raise "There is already an issue in the hierarchy with the title: #{issue.title}" if items[issue.title]
        items[issue.title] = issue

        if current_indent.length > last_indent.length
          # This is a sub-issue
          stack.last&.add_sub_issue!(issue, issue.owner.id)
        elsif current_indent.length == last_indent.length
          # This is a sibling issue
          stack.pop
          stack.last&.add_sub_issue!(issue, issue.owner.id)
        elsif current_indent.length < last_indent.length
          # if the current indentation is lower, then determine how much lower to
          # pop off a given number of items off the stack
          stack.pop((last_indent.length - current_indent.length) / 2 + 1)
          stack.last&.add_sub_issue!(issue, issue.owner.id)
        end

        stack.push(issue)
      when scanner.match?(/( |\t)/)
        # Scan all of the indentation
        current_indent = scanner.scan(/( |\t)+/) || ""
      when scanner.match?(/./)
        # By default if we didn't scan anything else we recognize, we will log the current state and raise an error
        char = scanner.getch

        debug_tree = tree.dup

        # Scan to the current position, then find the nearest newline and remove all text after that.
        next_newline_pos = debug_tree.index("\n", scanner.pos)
        prev_newline_pos = debug_tree.rindex("\n", scanner.pos)
        debug_tree = (debug_tree[0...next_newline_pos] || "") if prev_newline_pos
        # Arrow should be positioned relative to last newline
        arrow_pos = scanner.pos - prev_newline_pos - 2
        debug_tree << "\n" + " " * arrow_pos + "^"

        raise "Unrecognized character: #{char.inspect} at position #{scanner.pos} in tree:\n\n=====\n#{debug_tree}\n=====\n"
      end
    end

    items
  end
end
