# frozen_string_literal: true

require "test_helper"

class LabelsLabelComponentTest < ViewComponent::TestCase
  test "renders with a link" do
    label = create(:label)
    render_inline(Labels::LabelComponent.new(name: label.name, color: label.color, link: "/labels/#{label.id}"))
    assert_selector "[data-test-selector=label-content]", count: 1
    assert_selector "[data-test-selector=label-link]", count: 1
  end

  test "renders without a link" do
    label = create(:label)
    render_inline(Labels::LabelComponent.new(name: label.name, color: label.color))
    assert_selector "[data-test-selector=label-content]", count: 1
    assert_selector "[data-test-selector=label-link]", count: 0
  end

  test "figures out contrasting font color" do
    neon_label = Labels::LabelComponent.new(name: "neon color", color: "ceef2e")
    assert_equal "000000", neon_label.text_color
    dark_label = Labels::LabelComponent.new(name: "dark color", color: "54407b")
    assert_equal "ffffff", dark_label.text_color
  end
end
