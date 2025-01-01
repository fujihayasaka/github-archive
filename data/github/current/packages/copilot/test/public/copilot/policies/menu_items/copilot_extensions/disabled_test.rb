# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::CopilotExtensions::DisabledTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when copilot_extensions are disabled" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::ORGANIZATION_DESCRIPTION, name: "copilot_extensions")

          org = organization(copilot_extensions: :disabled)
          Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: org).component
        end
      end

      context "when copilot_extensions are not disabled" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::ORGANIZATION_DESCRIPTION, name: "copilot_extensions")

          org = organization(copilot_extensions: :enabled)
          Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      context "when copilot_extensions are disabled" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::BUSINESS_DESCRIPTION, name: "copilot_extensions")

          biz = business(copilot_extensions: :disabled)
          Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: biz).component
        end
      end

      context "when copilot_extensions are not disabled" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::BUSINESS_DESCRIPTION, name: "copilot_extensions")

          biz = business(copilot_extensions: :enabled)
          Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when copilot_extensions are disabled" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::ORGANIZATION_DESCRIPTION)

          org = organization(copilot_extensions: :disabled)
          hash = Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when copilot_extensions are not disabled" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::ORGANIZATION_DESCRIPTION)

          org = organization(copilot_extensions: :enabled)
          hash = Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end
    end

    context "when configuring a business" do
      context "when copilot_extensions are disabled" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::BUSINESS_DESCRIPTION)

          biz = business(copilot_extensions: :disabled)
          hash = Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when copilot_extensions are not disabled" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::CopilotExtensions::Disabled::BUSINESS_DESCRIPTION)

          biz = business(copilot_extensions: :enabled)
          hash = Copilot::Policies::MenuItems::CopilotExtensions::Disabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
