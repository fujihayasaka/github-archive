# typed: true
# frozen_string_literal: true

require "test_helper"

class TechStacksTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    @repo = Repositories::Public.find_active!(@repo.id)
    @tech_stacks = TechStacks.new(@repo)

    @go = TechStackName.lookup_by_name("Go")
    @java = TechStackName.lookup_by_name("Java")
    @ruby = TechStackName.lookup_by_name("Ruby")
    @python = TechStackName.lookup_by_name("Python")
    @npm = TechStackName.lookup_by_name("npm")
    @typescript = TechStackName.lookup_by_name("TypeScript")
    @stack_names = { "Go" => @go, "Java" => @java, "Ruby" => @ruby, "npm" => @npm,
      "Python" => @python, "django" => @django, "pip" => @pip, "gulp" => @gulp, "TypeScript" => @typescript }

    RepositoryTechProject.insert_all(
      [
        {
          path: "contoso/back-end-processor",
          repository_id: @repo.id,
          created_at: Time.now,
          updated_at: Time.now
        },
        {
          path: "contoso/front-end",
          repository_id: @repo.id,
          created_at: Time.now,
          updated_at: Time.now
        }
      ]
    )

    @tech_project1 = RepositoryTechProject.where(repository_id: @repo.id, path: "contoso/back-end-processor")
    @tech_project2 = RepositoryTechProject.where(repository_id: @repo.id, path: "contoso/front-end")

    RepositoryTechProjectStack.insert_all(
      [
        {
          repository_tech_project_id: @tech_project1[0].id,
          repository_id: @repo.id,
          settings: "{}",
          stack_name_id: @stack_names["Ruby"].id,
          created_at: Time.now,
          updated_at: Time.now
        },
        {
          repository_tech_project_id: @tech_project2[0].id,
          repository_id: @repo.id,
          settings: '{"npm.packageJsonPath": "contoso/front-end/package.json"}',
          stack_name_id: @stack_names["npm"].id,
          created_at: Time.now,
          updated_at: Time.now
        },
        {
          repository_tech_project_id: @tech_project2[0].id,
          repository_id: @repo.id,
          settings: '{"typescript.tsconfigPath": "contoso/front-end/typescript/tsconfig.json"}',
          stack_name_id: @stack_names["TypeScript"].id,
          created_at: Time.now,
          updated_at: Time.now
        }
      ]
    )

  end

  context "#tech_projects_retrieval" do
    test "join tech projects with stacks" do
      assert_equal @tech_project1.size, 1
      assert_equal @tech_project2.size, 1
      projects_with_stacks = @tech_stacks.projects_with_stacks_records

      assert_equal projects_with_stacks.size, 2
      paths = Set["contoso/back-end-processor", "contoso/front-end"]
      assert_equal paths.include?(projects_with_stacks[0].path), true
      assert_equal paths.include?(projects_with_stacks[1].path), true
    end

    test "get tech projects with stacks json" do
      response = JSON.parse(@tech_stacks.tech_project_stacks)
      response.each do |rp|
        if rp["path"].eql?("contoso/back-end-processor")
          assert_equal rp["stacks"].size, 1
        else
          #path here would be "contoso/front-end"
          assert_equal rp["stacks"].size, 2
        end
      end
    end

  end

end
