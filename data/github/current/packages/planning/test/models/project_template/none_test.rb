# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectTemplateNoneTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @template = ProjectTemplate::None.new
  end

  test "is a child of ProjectTemplate" do
    assert @template.is_a?(ProjectTemplate)
  end

  test "has the required attributes for rendering the UI" do
    assert ProjectTemplate::None.title
    assert ProjectTemplate::None.template_key
    assert ProjectTemplate::None.description
  end

  test "doesn't create any data" do
    assert_empty @template.columns
  end
end
