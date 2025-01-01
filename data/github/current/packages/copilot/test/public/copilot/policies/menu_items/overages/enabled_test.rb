# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::Overages::EnabledTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when allowing overages" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::Overages::Enabled::ORGANIZATION_DESCRIPTION, name: "copilot_overages")

          org = organization(overages: :enabled)
          Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: org).component
        end
      end

      context "when not allowing overages" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::Overages::Enabled::ORGANIZATION_DESCRIPTION, name: "copilot_overages")

          org = organization(overages: :disabled)
          Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      context "when allowing overages" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::Overages::Enabled::BUSINESS_DESCRIPTION, name: "copilot_overages")

          biz = business(overages: :enabled)
          Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: biz).component
        end
      end

      context "when not allowing Overages" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::Overages::Enabled::BUSINESS_DESCRIPTION, name: "copilot_overages")

          biz = business(overages: :disabled)
          Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when allowing overages" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::Overages::Enabled::ORGANIZATION_DESCRIPTION)

          org = organization(overages: :enabled)
          hash = Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing overages" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::Overages::Enabled::ORGANIZATION_DESCRIPTION)

          org = organization(overages: :disabled)
          hash = Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end
    end

    context "when configuring an business" do
      context "when allowing overages" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::Overages::Enabled::BUSINESS_DESCRIPTION)

          biz = business(overages: :enabled)
          hash = Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing overages" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::Overages::Enabled::BUSINESS_DESCRIPTION)

          biz = business(overages: :disabled)
          hash = Copilot::Policies::MenuItems::Overages::Enabled.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
