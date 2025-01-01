# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusCheckConfigTest < GitHub::TestCase
  test "adjectives default to the state name" do
    assert_equal "cancelled", StatusCheckConfig.for("cancelled").adjective
  end

  test "test custom adjectives" do
    assert_equal "successful", StatusCheckConfig.for(:success).adjective
    assert_equal "successful", StatusCheckConfig.for("success").adjective
    assert_equal "successful", StatusCheckConfig.for("SUCCESS").adjective
    assert_equal "failing", StatusCheckConfig.for(:failure).adjective
    assert_equal "errored", StatusCheckConfig.for("ERROR").adjective
    assert_equal "in progress", StatusCheckConfig.for("in_progress").adjective
    assert_equal "timed out", StatusCheckConfig.for(:timed_out).adjective
    assert_equal "marked stale by GitHub", StatusCheckConfig.for(:stale).adjective
  end

  test "test custom status_icon_color_class" do
    assert_equal "color-fg-success", StatusCheckConfig.for(:success).status_icon_color_class
    assert_equal "color-fg-danger", StatusCheckConfig.for(:failure).status_icon_color_class
    assert_equal "color-fg-danger", StatusCheckConfig.for(:error).status_icon_color_class
    assert_equal "neutral-check", StatusCheckConfig.for(:cancelled).status_icon_color_class
    assert_equal "hx_dot-fill-pending-icon", StatusCheckConfig.for(:in_progress).status_icon_color_class
    assert_equal "color-fg-danger", StatusCheckConfig.for(:timed_out).status_icon_color_class
    assert_equal "neutral-check", StatusCheckConfig.for(:stale).status_icon_color_class
  end

  def test_adjectives_default_to_the_state_name
    assert_equal "cancelled", StatusCheckConfig.adjective_state("cancelled")
  end

  def test_custom_adjectives
    assert_equal "successful", StatusCheckConfig.adjective_state(:success)
    assert_equal "successful", StatusCheckConfig.adjective_state("success")
    assert_equal "successful", StatusCheckConfig.adjective_state("SUCCESS")
    assert_equal "failing", StatusCheckConfig.adjective_state(:failure)
    assert_equal "errored", StatusCheckConfig.adjective_state("ERROR")
    assert_equal "in progress", StatusCheckConfig.adjective_state("in_progress")
    assert_equal "timed out", StatusCheckConfig.adjective_state(:timed_out)
    assert_equal "marked stale by GitHub", StatusCheckConfig.adjective_state(:stale)
  end
end
