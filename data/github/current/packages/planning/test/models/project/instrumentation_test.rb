# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectInstrumentationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner = create(:user)
    @project = create(:user_project, owner: @owner, public: false)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  test "publishes to hydro on project create" do
    project = create(:user_project, owner: @owner)

    assert_hydro_published({
      action: :CREATE,
      actor: Hydro::EntitySerializer.user(@owner),
      project_owner_user: Hydro::EntitySerializer.user(@owner),
      project: Hydro::EntitySerializer.project(project),
    }, schema: "github.v1.ProjectEvent")
  end

  test "publishes to hydro on project close" do
    @project.close

    assert_hydro_published({
      action: :CLOSE,
      actor: Hydro::EntitySerializer.user(@owner),
      project_owner_user: Hydro::EntitySerializer.user(@owner),
      project: Hydro::EntitySerializer.project(@project),
    }, schema: "github.v1.ProjectEvent")
  end

  test "publishes to hydro on project open" do
    project = create(:user_project, owner: @owner, closed_at: 1.day.ago)
    reset_hydro
    project.open

    assert_hydro_published({
      action: :OPEN,
      actor: Hydro::EntitySerializer.user(@owner),
      project_owner_user: Hydro::EntitySerializer.user(@owner),
      project: Hydro::EntitySerializer.project(project),
    }, schema: "github.v1.ProjectEvent")

  end

  test "publishes to hydro on project delete" do
    @project.destroy

    assert_hydro_published({
      action: :DELETE,
      actor: Hydro::EntitySerializer.user(@owner),
      project_owner_user: Hydro::EntitySerializer.user(@owner),
      project: Hydro::EntitySerializer.project(@project),
    }, schema: "github.v1.ProjectEvent")
  end

  test "publishes to hydro on project update" do
    @project.update!(public: true)

    assert_hydro_published({
      action: :UPDATE,
      actor: Hydro::EntitySerializer.user(@owner),
      project_owner_user: Hydro::EntitySerializer.user(@owner),
      project: Hydro::EntitySerializer.project(@project),
    }, schema: "github.v1.ProjectEvent")
  end
end
