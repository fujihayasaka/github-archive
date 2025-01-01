# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::PublicCodeSuggestions::UnconfiguredTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when neither allowing or blocking public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: "", name: "copilot_public_code_suggestions", type: "button")

          org = organization(public_code_suggestions: :unconfigured)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).component
        end
      end

      context "when allowing public code suggestions" do
        test "does not create a button" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(public_code_suggestions: :allowed)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).component
        end
      end

      context "when not allowing public code suggestions" do
        test "does not create a button" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(public_code_suggestions: :blocked)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      test "does not create a button" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        biz = Copilot::Business.new(create(:business))
        Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: biz).component
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when neither allowing or blocking public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: "")

          org = organization(public_code_suggestions: :unconfigured)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when allowing public code suggestions" do
        test "returns nil" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(public_code_suggestions: :allowed)
          assert_nil Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).to_h
        end
      end

      context "when not allowing public code suggestions" do
        test "returns nil" do
          GitHub::Menu::ButtonComponent.expects(:new).never

          org = organization(public_code_suggestions: :blocked)
          assert_nil Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: org).to_h
        end
      end
    end

    context "when configuring a business" do
      test "returns nil" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        biz = Copilot::Business.new(create(:business))
        assert_nil Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured.new(copilot_configurable: biz).to_h
      end
    end
  end
end if GitHub.copilot_enabled?
