# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUpdateTechProjectAndStackJobTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :tech_project_stacks_test)
  end

  setup do
    default_analysis = [{ "path" => "/", "tech_stack" => [{ "name" => "HTML", "size" => 1731 }, { "name" => "JavaScript", "size" => 10812 }, { "name" => "npm" }, { "name" => "React" }, { "name" => "Yarn" }] }]
    @expected_rpc_response = [*default_analysis, { "path" => "new_project/", "tech_stack" => [{ "name" => "C#", "size" => 1000 }, { "name" => "AspNetCore", "settings" => { "csproj_path" => "new_project/project.csproj" } }] }]

    disable_feature_flag(:active_job_default_to_write_connection)
  end

  context "#perform" do
    test "does not default to db write connection" do
      refute RepositoryUpdateTechProjectAndStackJob.default_to_write_connection?
    end

    test "doesn't fail when writing to db when the prefer primaries feature is enabled" do
      enable_feature_flag(:RepositoryUpdateTechProjectAndStackJob_primaries)

      GitRPC::Client.any_instance.stubs(:tech_project_stacks).returns(@expected_rpc_response)

      assert_difference(
        -> { RepositoryTechProject.where(repository_id: @repo.id).count } => 2,
        -> { RepositoryTechProjectStack.count } => 7,
        -> { TechStackName.count } => 7,
      ) do
        RepositoryUpdateTechProjectAndStackJob.perform_now(@repo.id)
      end
    end

    test "doesn't fail when writing to db when the prefer primaries feature is disabled" do
      disable_feature_flag(:RepositoryUpdateTechProjectAndStackJob_primaries)

      GitRPC::Client.any_instance.stubs(:tech_project_stacks).returns(@expected_rpc_response)

      assert_difference(
        -> { RepositoryTechProject.where(repository_id: @repo.id).count } => 2,
        -> { RepositoryTechProjectStack.count } => 7,
        -> { TechStackName.count } => 7,
      ) do
        RepositoryUpdateTechProjectAndStackJob.perform_now(@repo.id)
      end
    end
  end

  test "resolves tenant for multi tenant environment" do
    on_multi_tenant_enterprise do
      user = create(:emu)
      GitHub::CurrentTenant.set(user.enterprise_managed_business)
      repo = create(:repository, owner: user, from_example: :simple)

      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      RepositoryUpdateTechProjectAndStackJob.perform_now(repo.id)
      assert_equal repo.reload.tenant_id, GitHub::CurrentTenant.get.id
    end
  end
end
