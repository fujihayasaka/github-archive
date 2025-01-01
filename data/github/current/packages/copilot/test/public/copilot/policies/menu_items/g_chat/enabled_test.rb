# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::GChat::EnabledTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when allowing g_chat" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::GChat::Enabled::ORGANIZATION_DESCRIPTION, name: "copilot_g_chat")

          org = organization(g_chat: :enabled)
          Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: org).component
        end
      end

      context "when not allowing g_chat" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::GChat::Enabled::ORGANIZATION_DESCRIPTION, name: "copilot_g_chat")

          org = organization(g_chat: :disabled)
          Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      context "when allowing g_chat" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::GChat::Enabled::BUSINESS_DESCRIPTION, name: "copilot_g_chat")

          biz = business(g_chat: :enabled)
          Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: biz).component
        end
      end

      context "when not allowing g_chat" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::GChat::Enabled::BUSINESS_DESCRIPTION, name: "copilot_g_chat")

          biz = business(g_chat: :disabled)
          Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when allowing g_chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::GChat::Enabled::ORGANIZATION_DESCRIPTION)

          org = organization(g_chat: :enabled)
          hash = Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing g_chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::GChat::Enabled::ORGANIZATION_DESCRIPTION)

          org = organization(g_chat: :disabled)
          hash = Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end
    end

    context "when configuring an business" do
      context "when allowing g_chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::GChat::Enabled::BUSINESS_DESCRIPTION)

          biz = business(g_chat: :enabled)
          hash = Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing g_chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::GChat::Enabled::BUSINESS_DESCRIPTION)

          biz = business(g_chat: :disabled)
          hash = Copilot::Policies::MenuItems::GChat::Enabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
