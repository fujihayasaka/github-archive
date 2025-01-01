# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject::ViewDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  test "creates a default view on creation" do
    project = create(:memex_project, owner: @org)
    refute_empty project.memex_project_views
    assert_equal "View #{project.default_view.number}", project.default_view.name
    project_column_ids = project.memex_project_columns.filter(&:visible?).map(&:id)
    assert_same_elements project_column_ids, project.default_view.visible_fields
    refute_nil project.memex_project_views.first.priority
  end

  context "default_view" do
    test "returns the lowest priority view" do
      project = create(:memex_project, owner: @org)
      view_one = project.memex_project_views.first
      view_one.update_attribute(:priority, 2)
      view_two = create(:memex_project_view, memex_project: project, priority: 1)
      assert_equal(
        [view_one.id, view_two.id], # views in descending order of priority
        project.reload.prioritized_memex_project_views.map(&:id)
      )

      # The UI shows views in ascending order of priority
      # so view_two with the lowest priority should be the default
      assert_equal project.default_view.id, view_two.id
    end
  end

  context "memex_project_views" do
    test "memex_project exposes a prioritized_memex_project_views field" do
      memex = create(:memex_project, owner: @org, title: "My Memex Project")

      refute_nil memex.prioritized_memex_project_views
      assert_equal memex.prioritized_memex_project_views[0].class.name, "MemexProjectView"
    end

    test "memex_project implements a batched memex_project_views_with_filtered_layouts field" do
      memex1 = create(:memex_project, owner: @org, title: "My Memex Project")
      view1 = create(:memex_project_view, memex_project: memex1, name: "Board", layout: :board_layout)

      memex2 = create(:memex_project, owner: @org, title: "My Memex Project")
      view2 = create(:memex_project_view, memex_project: memex2, name: "Table", layout: :table_layout)

      memexes = [memex1, memex2]

      GitHub::PrefillAssociations.prefill_batch_method(memexes, :memex_project_views_with_filtered_layouts,
        [:board_layout])

      assert_max_query_count(0) do
        assert_equal 1, memex1.memex_project_views_with_filtered_layouts([:board_layout]).count
        assert_equal 0, memex2.memex_project_views_with_filtered_layouts([:board_layout]).count
      end
    end
  end
end
