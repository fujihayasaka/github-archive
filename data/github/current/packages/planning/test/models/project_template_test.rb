# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectTemplateTest < GitHub::TestCase
  fixtures do
    user = create(:user)
    GitHub.context.push(actor_id: user.id)
  end

  context "loading a template" do
    test "returns an error if the type is invalid" do
      assert_raises ProjectTemplate::InvalidTemplateTypeError do
        ProjectTemplate.load("YAY")
      end
    end

    test "returns a new instance of the correct template for the type" do
      template = ProjectTemplate.load("basic_kanban")
      assert_kind_of ProjectTemplate::BasicKanban, template
      assert_kind_of ProjectTemplate, template
    end

    test "returns a new instance of the correct template for the type using the GraphQL enum" do
      template = ProjectTemplate.load("BASIC_KANBAN")
      assert_kind_of ProjectTemplate::BasicKanban, template
      assert_kind_of ProjectTemplate, template
    end
  end

  context "class lookup" do
    test "dynamically loads valid names" do
      assert_equal ProjectTemplate::BasicKanban, ProjectTemplate.template_klass("basic_kanban")
    end

    test "dynamically loads valid names from GraphQL enums" do
      assert_equal ProjectTemplate::BasicKanban, ProjectTemplate.template_klass("BASIC_KANBAN")
    end

    test "raises an error for invalid names" do
      assert_raises ProjectTemplate::InvalidTemplateTypeError do
        ProjectTemplate.template_klass("sloth_party")
      end
    end

    test "raises an error for nil" do
      assert_raises ProjectTemplate::InvalidTemplateTypeError do
        ProjectTemplate.template_klass(nil)
      end
    end
  end

  context "UI helpers" do
    test "includes all project types" do
      template_classes = ProjectTemplate::TYPES.each do |type|
        template = ProjectTemplate.load(type)
        assert_includes ProjectTemplate.list, template.class
      end
    end

    test "format the class name for lookup and GraphQL" do
      assert_equal "PROJECT_TEMPLATE", ProjectTemplate.template_key
      assert_equal "BASIC_KANBAN", ProjectTemplate::BasicKanban.template_key
    end
  end

  context "template data" do
    test "converts columns to an ActiveRecord-friendly hash with required attributes" do
      template = ProjectTemplate.load("basic_kanban")

      assert_kind_of Hash, template.column_data.first
      assert template.column_data.first[:name]
    end
  end
end
