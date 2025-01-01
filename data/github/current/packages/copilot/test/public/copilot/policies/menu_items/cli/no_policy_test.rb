# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::Cli::NoPolicyTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      test "does not create a button" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        org = organization(cli: :enabled)
        Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: org).component
      end
    end

    context "when configuring a business" do
      context "when there is no policy for cli" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION, name: "cli")

          biz = business(cli: :no_policy)
          Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).component
        end
      end

      context "when cli is unconfigured" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION, name: "cli")

          biz = business(cli: :unconfigured)
          Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).component
        end
      end

      context "when there is a policy for cli" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION, name: "cli")

          biz = business(cli: :enabled)
          Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      test "returns nil" do
        org = organization(cli: :enabled)
        assert_nil Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: org).to_h
      end
    end

    context "when configuring a business" do
      context "when there is no policy for cli" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION)

          biz = business(cli: :no_policy)
          hash = Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when cli is unconfigured" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION)

          biz = business(cli: :unconfigured)
          hash = Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when there is a policy for cli" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::Cli::NoPolicy::DESCRIPTION)

          biz = business(cli: :enabled)
          hash = Copilot::Policies::MenuItems::Cli::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
