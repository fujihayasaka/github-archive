# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexTemplateTest < GitHub::TestCase
  fixtures do
    @admin  = create(:verified_user)
    @org    = create(:organization)

    @memex = create(:memex_project, owner: @org, title: "My Memex Project")
    @template = create(:memex_template, memex_project: @memex)
  end

  test "belongs to a memex project" do
    assert_equal @memex, @template.memex_project
    assert @template.active?
  end

  test "deleting the project marks the template as inactive" do
    assert_predicate @template, :active?
    refute_predicate @template, :inactive?

    @memex.soft_delete!(@admin)

    refute_predicate @template.reload, :active?
    assert_predicate @template, :inactive?
  end

  test "nullifies associated memex projects when destroyed" do
    first_memex_project = create(:memex_project, owner: @org, created_with_memex_template: @template)
    second_memex_project = create(:memex_project, owner: @org, created_with_memex_template: @template)

    assert_equal @template, first_memex_project.created_with_memex_template
    assert_equal @template, second_memex_project.created_with_memex_template

    @template.destroy!

    assert_nil first_memex_project.reload.created_with_memex_template_id
    assert_nil second_memex_project.reload.created_with_memex_template_id
  end

  test "destroys associated memex_project_links when destroyed" do
    memex_project_link = create(:memex_project_link, source_type: "Organization", source_id: @org.id, memex_project: @memex)

    assert_difference "MemexProjectLink.count", -1 do
      @template.destroy!
    end

    assert_equal @template, @memex.memex_template
    assert_nil MemexProjectLink.find_by(id: memex_project_link.id)
  end

  test "destroys associated memex_project_links when template becomes inactive" do
    memex_project_link = create(:memex_project_link, source_type: "Organization", source_id: @org.id, memex_project: @memex)

    assert_difference "MemexProjectLink.count", -1 do
      @template.update!(active: false)
    end

    assert_equal @template, @memex.memex_template
    assert_nil MemexProjectLink.find_by(id: memex_project_link.id)
  end

  test "to_hash on new record" do
    memex_template = MemexTemplate.new
    expected_hash = {
      updatedAt: nil,
      createdAt: nil,
      id: nil,
      isActive: true,
    }

    assert_equal expected_hash, memex_template.to_hash
  end

  test "to_hash on persisted record" do
    travel_to Time.zone.parse("2019-01-01 12:00:00")

    memex_project = create(:memex_project, owner: @org)
    memex_template = create(:memex_template, memex_project: memex_project, active: false)
    expected_hash = {
      updatedAt: "2019-01-01T11:00:00Z",
      createdAt: "2019-01-01T11:00:00Z",
      id: memex_template.id,
      isActive: false,
    }

    assert_equal expected_hash, memex_template.to_hash
  end
end
