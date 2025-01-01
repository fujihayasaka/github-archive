# typed: false
# frozen_string_literal: true

require "test_helper"

module TechProjectStackTestHelper
  def compare_tech_projects(repository_id, expected_tech_projects, actual_tech_projects, added_tech_projects_check = true)
    actual_tech_projects.each do |project|
      expected_project = expected_tech_projects.find { |pr| pr.path == project.path }
      refute_nil expected_project, "expected_project should not be nil"
      assert_equal repository_id, project.repository_id, "repository_id of tech project record should be equal to repository_id"
      marked_for_destruction_count = 0
      project.repository_tech_project_stacks.each do |stack|
        expected_stack = expected_project.stacks.find { |st| st.id == stack.stack_name_id }
        if !expected_stack
          assert stack.marked_for_destruction?, "stack record should be marked for destruction"
          marked_for_destruction_count += 1
        else
          assert_equal repository_id, stack.repository_id, "repository_id of stack record should be equal to repository_id"
          if expected_stack.size
            assert_equal expected_stack.size, stack.size, "size should be equal to analysed size"
          else
            assert_nil stack.size, "stack size should be nil"
          end
          if expected_stack.settings
            assert_equal expected_stack.settings, stack.settings, "settings should be equal to analysed settings"
          else
            assert_nil stack.settings, "stack settings should be nil"
          end
        end
      end
      if added_tech_projects_check
        assert_equal 0, marked_for_destruction_count, "no stack record should be marked for destruction"
      end
      assert_equal expected_project.stacks.length + marked_for_destruction_count, project.repository_tech_project_stacks.length, "expected stacks length + marked_for_destruction_count and actual stacks record length should be same"
    end
  end
end

class TechProjectStackAnalyzerTest < GitHub::TestCase
  include TechProjectStackTestHelper
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @repo = create(:repository, from_example: :tech_project_stacks_test)
  end

  setup do
    @repo = Repositories::Public.find_active!(@repo.id)
    @analyzer = TechProjectStackAnalyzer.new(@repo)
    @analyzer.analyze
  end

  def default_analysis
    [{ "path" => "/", "tech_stack" => [{ "name" => "HTML", "size" => 1731 }, { "name" => "JavaScript", "size" => 10812 }, { "name" => "npm" }, { "name" => "React" }, { "name" => "Yarn" }] }]
  end

  def stub_tech_project_analysis(analysis_results)
    GitRPC::Client.any_instance.stubs(:tech_project_stacks).returns(analysis_results)
  end

  def expected_existing_tech_projects
    rpc_response = [{ "path" => "/", "tech_stack" => [{ "name" => "HTML", "size" => 1731 }, { "name" => "JavaScript", "size" => 10812 }, { "name" => "npm" }, { "name" => "React" }, { "name" => "Yarn" }] }]
    rpc_to_tech_project_mapper rpc_response
  end

  def tech_stack_name_record(name)
    record = TechStackName.find_by_name(name)
    # all the stack name should have been added during analyze step.
    refute_nil record, "Tech stack {{name}} should be added"
    record
  end

  def rpc_to_tech_project_mapper(tech_projects)
    mapped_projects = tech_projects.map { |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) }) }
    mapped_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = tech_stack_name_record(stack.name).id
      end
    end
    mapped_projects
  end

  context "#existing_tech_project_records" do
    test "retrieves the exiting tech projects" do
      analyzed_tech_projects = TechStacks.new(@repo).projects_with_stacks_records
      expected_tech_projects = expected_existing_tech_projects

      assert_equal expected_tech_projects.length, analyzed_tech_projects.length
      compare_tech_projects @repo.id, expected_tech_projects, analyzed_tech_projects
    end
  end

  context "analyze tech project"  do
    test "new tech project added" do
      expected_rpc_response = [*default_analysis, { "path" => "new_project/", "tech_stack" => [{ "name" => "C#", "size" => 1000 }, { "name" => "AspNetCore", "settings" => { "csproj_path" => "new_project/project.csproj" } }] }]
      stub_tech_project_analysis expected_rpc_response
      @analyzer.analyze
      analyzed_tech_projects = TechStacks.new(@repo).projects_with_stacks_records
      expected_tech_projects = rpc_to_tech_project_mapper expected_rpc_response
      assert_equal expected_tech_projects.length, analyzed_tech_projects.length
      compare_tech_projects @repo.id, expected_tech_projects, analyzed_tech_projects
    end

    test "existing tech project, new stack added and old stack deleted" do
      expected_rpc_response = [*default_analysis]
      expected_rpc_response[0]["tech_stack"].append({ "name" => "AspNetCore", "settings" => { "csproj_path" => "project.csproj" } }).delete_if { |stack| stack["name"] == "HTML" }
      stub_tech_project_analysis expected_rpc_response
      @analyzer.analyze
      analyzed_tech_projects = TechStacks.new(@repo).projects_with_stacks_records
      expected_tech_projects = rpc_to_tech_project_mapper expected_rpc_response
      assert_equal expected_tech_projects.length, analyzed_tech_projects.length
      compare_tech_projects @repo.id, expected_tech_projects, analyzed_tech_projects
    end
  end



  context "#clear_analysis" do
    test "clears the tech projects for a repository" do
      @analyzer.clear_analysis
      tech_projects = TechStacks.new(@repo).projects_with_stacks_records
      assert_equal [], tech_projects
    end
  end
end

class TechProjectStackAnalyzerDiffTest < GitHub::TestCase

  include TechProjectStackTestHelper
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @repo = create(:repository)
    @html = TechStackName.lookup_by_name("HTML")
    @js   = TechStackName.lookup_by_name("JavaScript")
    @css  = TechStackName.lookup_by_name("CSS")
    @python = TechStackName.lookup_by_name("Python")
    @django = TechStackName.lookup_by_name("django")
    @asp_net_core = TechStackName.lookup_by_name("AspNetCore")
    @npm = TechStackName.lookup_by_name("npm")
    @c_sharp = TechStackName.lookup_by_name("C#")
    @stack_names = { "HTML" => @html, "JavaScript" => @js, "CSS" => @css, "npm" => @npm, "Python" => @python, "django" => @django, "AspNetCore" => @asp_net_core, "C#" => @c_sharp }
  end

  test "new repository tech projects analysis" do
    existing_projects = []
    analysed_projects = [
      {
        "path" => "/",
        "tech_stack" => [
          { "name" => "HTML", "size" => 2665 },
          { "name" => "JavaScript", "size" => 22548 },
          { "name" => "CSS", "size" => 473 },
          { "name" => "C#", "size" => 5391 },
          { "name" => "npm", "settings" => { "package_json_path" => "package.json" } },
          { "name" => "AspNetCore" }
        ]
      },
      {
        "path" => "/project",
        "tech_stack" => [
          { "name" => "CSS", "size" => 400 },
          { "name" => "Python", "size" => 5000 },
          { "name" => "django" },
          { "name" => "HTML", "size" => 800 }
        ]
      }
    ]
    analysed_projects  = analysed_projects.map do |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) })
    end
    analysed_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = @stack_names[stack.name].id
      end
    end

    diff = TechProjectStackAnalyzer::Diff.new(@repo.id, existing_projects, analysed_projects)

    assert_equal analysed_projects.length, diff.to_add_tech_projects.length
    compare_tech_projects @repo.id, analysed_projects, diff.to_add_tech_projects
    assert_equal [], diff.to_delete_tech_projects
    assert_equal [], diff.to_update_tech_projects
  end

  test "delete update and add tech projects" do
    existing_projects = [
      {
        "path" => "/",
        "tech_stack" => [
          { "name" => "JavaScript", "size" => 22548 },
          { "name" => "CSS", "size" => 473 },
          { "name" => "C#", "size" => 8000 },
          { "name" => "npm", "settings" => { "package_json_path" => "package.json" } },
          { "name" => "AspNetCore", "settings" => { "csproj_path" => "project.csrpoj" } }
        ]
      },
      {
        "path" => "/deleted_project",
        "tech_stack" => [
          { "name" => "CSS", "size" => 400 },
          { "name" => "Python", "size" => 5000 }
        ]
      }
    ]
    analysed_projects = [
      {
        "path" => "/",
        "tech_stack" => [
          { "name" => "HTML", "size" => 2665 },
          { "name" => "JavaScript", "size" => 22548 },
          { "name" => "C#", "size" => 8000 },
          { "name" => "npm", "settings" => { "package_json_path" => "package.json" } },
          { "name" => "AspNetCore", "settings" => { "csproj_path" => "project.csrpoj" } }
        ]
      },
      {
        "path" => "/new_project",
        "tech_stack" => [
          { "name" => "CSS", "size" => 400 },
          { "name" => "Python", "size" => 5000 },
          { "name" => "django" },
          { "name" => "HTML", "size" => 800 }
        ]
      }
    ]
    deleted_stack_ids_map = { "/" => [@css.id] }
    new_stack_ids_map = { "/" => [@html.id] }
    analysed_tech_projects = analysed_projects.map { |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) }) }
    analysed_tech_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = @stack_names[stack.name].id
      end
    end
    analysed_tech_projects_copy = analysed_projects.map { |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) }) }
    analysed_tech_projects_copy.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = @stack_names[stack.name].id
      end
    end
    analysed_tech_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = @stack_names[stack.name].id
      end
    end
    existing_projects  = existing_projects.map { |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) }) }

    existing_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = @stack_names[stack.name].id
      end
    end
    pr_id = 0
    stack_id = 0
    existing_projects = existing_projects.map do |project|
      pr_id += 1
      exiting_project = RepositoryTechProject.new({ id: pr_id, repository_id: @repo.id, path: project.path })
      exiting_project.repository_tech_project_stacks = project.stacks.map do |stack|
        stack_id += 1
        RepositoryTechProjectStack.new({ id: stack_id, repository_tech_project_id: pr_id, stack_name_id: stack.id, size: stack.size, settings: stack.settings, repository_id: @repo.id })
      end
      exiting_project
    end

    diff = TechProjectStackAnalyzer::Diff.new(@repo.id, existing_projects, analysed_tech_projects)
    analysed_tech_projects = analysed_tech_projects_copy
    assert_equal 1, diff.to_add_tech_projects.length

    compare_tech_projects @repo.id, analysed_tech_projects, diff.to_add_tech_projects
    diff.to_add_tech_projects.each do |project|
      analysed_tech_projects.delete_if { |pr| pr.path == project.path }
    end
    assert_equal 1, diff.to_delete_tech_projects.length
    assert_equal  [2], diff.to_delete_tech_projects

    assert_equal analysed_tech_projects.length, diff.to_update_tech_projects.length

    compare_tech_projects @repo.id, analysed_tech_projects, diff.to_update_tech_projects, false
    diff.to_update_tech_projects.each do |project|
      project.repository_tech_project_stacks.each do |stack|
        if stack.marked_for_destruction?
          assert_includes deleted_stack_ids_map[project.path], stack.stack_name_id, "stack should be in deleted stacks ids list"
        elsif !stack.id
          assert_includes new_stack_ids_map[project.path], stack.stack_name_id, "stack should be in new stack ids list"
        end
      end
    end
  end
end
