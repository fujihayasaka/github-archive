# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::AChat::DisabledTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when blocking chat suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::AChat::Disabled::ORGANIZATION_DESCRIPTION, name: "copilot_a_chat")

          org = organization(a_chat: :disabled)
          Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: org).component
        end
      end

      context "when not blocking chat suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::AChat::Disabled::ORGANIZATION_DESCRIPTION, name: "copilot_a_chat")

          org = organization(a_chat: :enabled)
          Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      context "when blocking chat suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::AChat::Disabled::BUSINESS_DESCRIPTION, name: "copilot_a_chat")

          biz = business(a_chat: :disabled)
          Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: biz).component
        end
      end

      context "when not blocking chat suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::AChat::Disabled::BUSINESS_DESCRIPTION, name: "copilot_a_chat")

          biz = business(a_chat: :enabled)
          Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when blocking chat suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::AChat::Disabled::ORGANIZATION_DESCRIPTION)

          org = organization(a_chat: :disabled)
          hash = Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when not blocking chat suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::AChat::Disabled::ORGANIZATION_DESCRIPTION)

          org = organization(a_chat: :enabled)
          hash = Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end
    end

    context "when configuring a business" do
      context "when blocking chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::AChat::Disabled::BUSINESS_DESCRIPTION)

          biz = business(a_chat: :disabled)
          hash = Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when not blocking chat" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::AChat::Disabled::BUSINESS_DESCRIPTION)

          biz = business(a_chat: :enabled)
          hash = Copilot::Policies::MenuItems::AChat::Disabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
