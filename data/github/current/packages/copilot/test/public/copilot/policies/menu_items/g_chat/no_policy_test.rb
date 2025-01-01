# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::GChat::NoPolicyTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      test "does not create a button for an org" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        org = organization(g_chat: :disabled)
        Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: org).component
      end

      test "does not create a button for a standalone business" do
        GitHub::Menu::ButtonComponent.expects(:new).never
        Copilot::Policies::MenuItems::Base.any_instance.stubs(:standalone_business?).returns(true)

        org = organization(g_chat: :disabled)
        Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: org).component
      end
    end

    context "when configuring a business" do
      context "when set to no policy" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::GChat::NoPolicy::DESCRIPTION, name: "copilot_g_chat")

          biz = business(g_chat: :no_policy)
          Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: biz).component
        end
      end

      context "when not set to no policy" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::GChat::NoPolicy::DESCRIPTION, name: "copilot_g_chat")

          biz = business(g_chat: :enabled)
          Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      test "returns nil" do
        org = organization(g_chat: :disabled)
        assert_nil Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: org).to_h
      end
    end

    context "when configuring a business" do
      context "when set to no policy" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::GChat::NoPolicy::DESCRIPTION)

          biz = business(g_chat: :no_policy)
          hash = Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when not set to no policy" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::GChat::NoPolicy::DESCRIPTION)

          biz = business(g_chat: :enabled)
          hash = Copilot::Policies::MenuItems::GChat::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
