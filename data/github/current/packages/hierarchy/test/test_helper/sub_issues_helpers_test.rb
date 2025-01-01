# typed: true
# frozen_string_literal: true

require "test_helper"

class SubIssuesHelpersTest < GitHub::TestCase
  include SubIssuesHelpers

  context "create_hierarchy!" do
    test "can create a single issue" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
      HIERARCHY

      assert_equal "parent", issues["parent"]&.title
    end

    test "can create a parent-child relationship" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
        - child
      HIERARCHY

      assert_includes issues["parent"]&.sub_issues, issues["child"]
    end

    test "can create child siblings" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
        - child1
        - child2
      HIERARCHY

      assert_includes issues["parent"]&.sub_issues, issues["child1"]
      assert_includes issues["parent"]&.sub_issues, issues["child2"]
    end

    test "can create siblings at multiple levels" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent1
        - child1.1
        - child1.2
      - parent2
        - child2.1
        - child2.2
      HIERARCHY

      assert_includes issues["parent1"]&.sub_issues, issues["child1.1"]
      assert_includes issues["parent1"]&.sub_issues, issues["child1.2"]
      assert_includes issues["parent2"]&.sub_issues, issues["child2.1"]
      assert_includes issues["parent2"]&.sub_issues, issues["child2.2"]
    end

    test "can create sibling items" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
      - parent2
      HIERARCHY

      assert_equal "parent", issues["parent"]&.title
      assert_equal "parent2", issues["parent2"]&.title
    end

    test "can create grandchildren" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
        - child
          - grandchild
      HIERARCHY

      assert_includes issues["parent"]&.sub_issues, issues["child"]
      assert_includes issues["child"]&.sub_issues, issues["grandchild"]
    end

    test "can create very nested children" do
      issues = create_hierarchy! <<~HIERARCHY
      - parent
        - child1
          - child2
            - child3
              - child4
                - child5
                  - child6
                    - child7
      HIERARCHY

      assert_includes issues["parent"]&.sub_issues, issues["child1"]
      assert_includes issues["child1"]&.sub_issues, issues["child2"]
      assert_includes issues["child2"]&.sub_issues, issues["child3"]
      assert_includes issues["child3"]&.sub_issues, issues["child4"]
      assert_includes issues["child4"]&.sub_issues, issues["child5"]
      assert_includes issues["child5"]&.sub_issues, issues["child6"]
      assert_includes issues["child6"]&.sub_issues, issues["child7"]
    end

    test "can create complex hierarchy structures" do
      issues = create_hierarchy! <<~HIERARCHY
      - issue1
        - issue2
          - issue3
          - issue4
        - issue5
        - issue6
      - issue7
      - issue8
      - issue9
        - issue10
          - issue11
      - issue12
        - issue13
          - issue14
      HIERARCHY

      assert_includes issues["issue1"]&.sub_issues, issues["issue2"]
      assert_includes issues["issue2"]&.sub_issues, issues["issue3"]
      assert_includes issues["issue2"]&.sub_issues, issues["issue4"]
      assert_includes issues["issue1"]&.sub_issues, issues["issue5"]
      assert_includes issues["issue1"]&.sub_issues, issues["issue6"]
      assert_includes issues["issue9"]&.sub_issues, issues["issue10"]
      assert_includes issues["issue10"]&.sub_issues, issues["issue11"]
      assert_includes issues["issue12"]&.sub_issues, issues["issue13"]
      assert_includes issues["issue13"]&.sub_issues, issues["issue14"]
    end

    test "can handle multi-level indentation jumps" do
      issues = create_hierarchy! <<~HIERARCHY
      - issue1
        - issue2
          - issue3
            - issue4
              - issue5
        - issue6
          - issue7
            - issue8
        - issue9
          - issue10
            - issue11
              - issue12
          - issue13
            - issue14
      HIERARCHY

      assert_includes issues["issue1"]&.sub_issues, issues["issue2"]
      assert_includes issues["issue2"]&.sub_issues, issues["issue3"]
      assert_includes issues["issue3"]&.sub_issues, issues["issue4"]
      assert_includes issues["issue4"]&.sub_issues, issues["issue5"]
      assert_includes issues["issue1"]&.sub_issues, issues["issue6"]
      assert_includes issues["issue6"]&.sub_issues, issues["issue7"]
      assert_includes issues["issue7"]&.sub_issues, issues["issue8"]
      assert_includes issues["issue9"]&.sub_issues, issues["issue10"]
      assert_includes issues["issue10"]&.sub_issues, issues["issue11"]
      assert_includes issues["issue11"]&.sub_issues, issues["issue12"]
      assert_includes issues["issue9"]&.sub_issues, issues["issue13"]
      assert_includes issues["issue13"]&.sub_issues, issues["issue14"]
    end

    test "can create hierarchies from existing issues" do
      repository = create(:repository)
      issue1 = create(:issue, repository:)
      issue2 = create(:issue, repository:)
      issue3 = create(:issue, repository:)
      issue4 = create(:issue, repository:)
      issue5 = create(:issue, repository:)
      issue6 = create(:issue, repository:)
      issue7 = create(:issue, repository:)
      issue8 = create(:issue, repository:)
      issue9 = create(:issue, repository:)
      issue10 = create(:issue, repository:)
      issue11 = create(:issue, repository:)

      hierarchy = <<~HIERARCHY
      - #{issue1}
        - #{issue2}
          - #{issue3}
          - #{issue4}
        - #{issue5}
        - #{issue6}
      - #{issue7}
      - #{issue8}
      - #{issue9}
        - #{issue10}
          - #{issue11}
      HIERARCHY
      create_hierarchy!(hierarchy, issues: [issue1, issue2, issue3, issue4, issue5, issue6, issue7, issue8, issue9, issue10, issue11])

      assert_includes issue1.sub_issues, issue2
      assert_includes issue2.sub_issues, issue3
      assert_includes issue2.sub_issues, issue4
      assert_includes issue1.sub_issues, issue5
      assert_includes issue1.sub_issues, issue6
      assert_includes issue9.sub_issues, issue10
      assert_includes issue10.sub_issues, issue11
    end

    test "does not allow duplicate names" do
      assert_raises_with_message(StandardError, "There is already an issue in the hierarchy with the title: parent") do
        create_hierarchy! <<~HIERARCHY
        - parent
        - parent
        HIERARCHY
      end
    end

    test "prints error message when an unknown character is encountered" do
      msg = <<~ERROR_MSG
      Unrecognized character: "|" at position 12 in tree:

      =====
      - parent
        | child
        ^
      =====
      ERROR_MSG

      assert_raises_with_message(StandardError, msg) do
        create_hierarchy! <<~HIERARCHY
        - parent
          | child
        - root
        HIERARCHY
      end

      msg = <<~ERROR_MSG
      Unrecognized character: "|" at position 20 in tree:

      =====
      - parent
        - child
      | root
      ^
      =====
      ERROR_MSG

      assert_raises_with_message(StandardError, msg) do
        create_hierarchy! <<~HIERARCHY
        - parent
          - child
        | root
        HIERARCHY
      end
    end
  end
end
