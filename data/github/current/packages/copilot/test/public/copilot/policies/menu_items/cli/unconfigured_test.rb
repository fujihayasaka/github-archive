# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::Cli::UnconfiguredTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when cli is unconfigured" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: "", name: "cli", type: "button")

          org = organization(cli: :unconfigured)
          Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).component
        end
      end

      context "when cli is disabled" do
        test "does not create a button" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(cli: :disabled)
          Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).component
        end
      end

      context "when cli is enabled" do
        test "does not create a button" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(cli: :enabled)
          Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      test "does not create a button" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        biz = Copilot::Business.new(create(:business))
        Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: biz).component
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when cli is unconfigured" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: "")

          org = organization(cli: :unconfigured)
          hash = Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when cli is enabled" do
        test "returns nil" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(cli: :enabled)
          assert_nil Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).to_h
        end
      end

      context "when cli is disabled" do
        test "returns nil" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(cli: :disabled)
          assert_nil Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: org).to_h
        end
      end
    end

    context "when configuring a business" do
      test "returns nil" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        biz = Copilot::Business.new(create(:business))
        assert_nil Copilot::Policies::MenuItems::Cli::Unconfigured.new(copilot_configurable: biz).to_h
      end
    end
  end
end if GitHub.copilot_enabled?
