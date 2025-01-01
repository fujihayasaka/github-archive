# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMemexProjectItemDependencyTest < GitHub::TestCase
  setup do
    @pull = create(:pull_request, :disable_disk_access)

    @memexes = create_list(:memex_project, 2)
    @memex_items = @memexes.map { |memex| create(:memex_project_item, content: @pull, memex_project: memex) }
  end

  test "destroying pull request destroys associated memex_project_items" do
    assert_equal 2, @pull.memex_project_items.length
    assert_same_elements @memex_items, @pull.memex_project_items

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @pull.destroy }

    @memex_items.each { |memex_item| refute MemexProjectItem.exists?(memex_item.id) }
  end

  context "touch_memex_project_items" do
    test "touch_memex_project_items_job is enqueued when pull request is touched" do
      @pull.touch
      assert_enqueued_with(job: TouchMemexProjectItemsJob, args: [@pull])
    end
  end

  context "#csv_column_value" do
    test "should return a proper value" do
      assert_equal @pull.url, @pull.csv_column_value
    end
  end
end
