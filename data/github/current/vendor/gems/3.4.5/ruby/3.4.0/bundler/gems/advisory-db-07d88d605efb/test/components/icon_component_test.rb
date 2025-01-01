# frozen_string_literal: true

require "test_helper"

class IconComponentTest < ViewComponent::TestCase
  def assert_svg_matches_file(filename, actual_svg)
    expected_svg_path = Rails.root.join("app/assets/images/icons", filename)
    assert_predicate expected_svg_path, :exist?
    expected_svg = Capybara::Node::Simple.new(expected_svg_path.read).find("svg")
    assert_predicate expected_svg, :present?
    expected_paths = expected_svg.all("path")
    assert_predicate expected_paths, :present?
    actual_paths = actual_svg.all("path")
    assert_equal expected_paths.count, actual_paths.count

    actual_paths.each_with_index do |path, index|
      expected_path = expected_paths[index]
      assert_equal expected_path.native.to_s, path.native.to_s
    end
  end

  setup do
    @svg_dir = Rails.root.join("app/assets/images/icons")
  end

  test "renders a known Octicon" do
    icon = IconComponent.new(icon: "check")

    render_inline(icon)

    assert_selector "svg.octicon.octicon-check", count: 1 do |svg|
      assert_selector svg, "path" # The SVG must contain at least one path
    end
  end

  test "renders a custom SVG icon" do
    icon = IconComponent.new(icon: "open-new")

    render_inline(icon)

    assert_selector "svg.octicon.octicon-inline-svg", count: 1 do |svg|
      assert_svg_matches_file "open-new-small.svg", svg
    end
  end

  test "defaults to a small Octicon" do
    icon = IconComponent.new(icon: "check")

    render_inline(icon)

    assert_selector "svg.octicon" do |svg|
      assert_equal 16, svg["width"].to_i
      assert_equal 16, svg["height"].to_i
      assert_equal "0 0 16 16", svg["viewbox"]
    end
  end

  test "renders a medium Octicon" do
    icon = IconComponent.new(icon: "check", size: :medium)

    render_inline(icon)

    assert_selector "svg.octicon" do |svg|
      # Actual dimensions depend on the current
      # version of primer_view_components.
      assert_operator 16, :<, svg["width"].to_i
      assert_operator 16, :<, svg["height"].to_i
      assert_equal "0 0 24 24", svg["viewbox"]
    end
  end

  test "renders a medium SVG icon" do
    icon = IconComponent.new(icon: "open-new", size: :medium)

    render_inline(icon)

    assert_selector "svg.octicon" do |svg|
      # Actual dimensions depend on the current
      # version of primer_view_components.
      assert_operator 16, :<, svg["width"].to_i
      assert_operator 16, :<, svg["height"].to_i
      assert_equal "0 0 24 24", svg["viewbox"]
    end
  end

  test "accepts Primer styling for an Octicon" do
    icon = IconComponent.new(icon: "check", mr: 2)

    render_inline(icon)

    assert_selector "svg.octicon.mr-2"
  end

  test "accepts Primer styling for an SVG icon" do
    icon = IconComponent.new(icon: "open-new", mr: 2)

    render_inline(icon)

    assert_selector "svg.octicon.mr-2"
  end

  test "renders no leading or trailing whitespace for an Octicon" do
    icon = IconComponent.new(icon: "check")

    render_inline(icon)

    assert_equal rendered_content.strip, rendered_content
  end

  test "renders no leading or trailing whitespace for an SVG icon" do
    icon = IconComponent.new(icon: "open-new")

    render_inline(icon)

    assert_equal rendered_content.strip, rendered_content
  end

  test "raises an error if no Octicon or SVG icon is available" do
    icon = IconComponent.new(icon: "bogus")

    assert_raises do
      render_inline(icon)
    end
  end
end
