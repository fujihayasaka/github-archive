# frozen_string_literal: true

require "test_helper"

class CheckComponentTest < ViewComponent::TestCase
  test "builds a message" do
    component = CheckComponent.new(check: {
      "name" => "Must Make Sense Check",
      "status" => "failed",
      "message" => "Check Raised Exception - This doesn't make sense",
    })
    assert_equal "Failed: Check Raised Exception - This doesn't make sense", component.message

    component = CheckComponent.new(check: {
      "name" => "Must Make Sense Check",
      "status" => "failed",
    })
    assert_equal "Failed", component.message

    component = CheckComponent.new(check: {
      "name" => "Must Make Sense Check",
    })
    assert_equal "Unknown", component.message
  end

  test "maps status to icons" do
    render_inline(CheckComponent.new(check: { "status" => "passed" }))
    assert_selector "[data-test-selector=passed-check-icon]", count: 1
    assert_selector "[data-test-selector=failed-check-icon]", count: 0

    render_inline(CheckComponent.new(check: { "status" => "failed" }))
    assert_selector "[data-test-selector=failed-check-icon]", count: 1
    assert_selector "[data-test-selector=warning-check-icon]", count: 0

    render_inline(CheckComponent.new(check: { "status" => "warning" }))
    assert_selector "[data-test-selector=warning-check-icon]", count: 1
    assert_selector "[data-test-selector=running-check-icon]", count: 0

    render_inline(CheckComponent.new(check: { "status" => "running" }))
    assert_selector "[data-test-selector=running-check-icon]", count: 1
    assert_selector "[data-test-selector=queued-check-icon]", count: 0

    render_inline(CheckComponent.new(check: { "status" => "queued" }))
    assert_selector "[data-test-selector=queued-check-icon]", count: 1
    assert_selector "[data-test-selector=blank-check-icon]", count: 0

    render_inline(CheckComponent.new(check: {}))
    assert_selector "[data-test-selector=blank-check-icon]", count: 1
    assert_selector "[data-test-selector=passed-check-icon]", count: 0
  end

  # Check class for testing. Includes an acronym known to Rails inflections for
  # testing name generation.
  check_class = TheCVEReviewMustBeAwesomeCheck = Class.new

  test "generates a friendly name" do
    render_inline(CheckComponent.new(check: { "check_class" => check_class }))
    assert_selector "[data-test-selector=check-name]", text: "The CVE review must be awesome"
  end
end
