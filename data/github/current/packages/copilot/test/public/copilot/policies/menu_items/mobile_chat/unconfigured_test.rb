# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::MobileChat::UnconfiguredTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    test "does not create a button" do
      GitHub::Menu::ButtonComponent.expects(:new).never

      org = organization(mobile_chat: :disabled)
      Copilot::Policies::MenuItems::MobileChat::Unconfigured.new(copilot_configurable: org).component
    end
  end

  context "#to_h" do
    test "returns nil" do
      org = organization(mobile_chat: :disabled)
      assert_nil Copilot::Policies::MenuItems::MobileChat::Unconfigured.new(copilot_configurable: org).to_h
    end
  end
end if GitHub.copilot_enabled?
