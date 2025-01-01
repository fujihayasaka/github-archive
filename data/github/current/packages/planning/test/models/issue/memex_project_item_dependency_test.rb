# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueMemexProjectItemDependencyTest < GitHub::TestCase
  setup do
    @issue = create(:issue)

    @memexes = create_list(:memex_project, 2)
    @memex_items = @memexes.map { |memex| create(:memex_project_item, content: @issue, memex_project: memex) }
  end

  test "destroying issue destroys associated memex_project_items" do
    assert_equal 2, @issue.memex_project_items.length
    assert_same_elements @memex_items, @issue.memex_project_items

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @issue.destroy }

    @memex_items.each { |memex_item| refute MemexProjectItem.exists?(memex_item.id) }
  end
end
