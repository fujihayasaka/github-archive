# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::PublicCodeSuggestions::AllowedTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      context "when allowing public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::ORGANIZATION_DESCRIPTION, name: "copilot_public_code_suggestions")

          org = organization(public_code_suggestions: :allowed)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: org).component
        end
      end

      context "when not allowing public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::ORGANIZATION_DESCRIPTION, name: "copilot_public_code_suggestions")

          org = organization(public_code_suggestions: :blocked)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: org).component
        end
      end
    end

    context "when configuring a business" do
      context "when allowing public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::BUSINESS_DESCRIPTION, name: "copilot_public_code_suggestions")

          biz = business(public_code_suggestions: :allowed)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: biz).component
        end
      end

      context "when not allowing public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::BUSINESS_DESCRIPTION, name: "copilot_public_code_suggestions")

          biz = business(public_code_suggestions: :blocked)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      context "when allowing public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::ORGANIZATION_DESCRIPTION)

          org = organization(public_code_suggestions: :allowed)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::ORGANIZATION_DESCRIPTION)

          org = organization(public_code_suggestions: :blocked)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: org).to_h
          assert_equal expected, hash
        end
      end
    end

    context "when configuring a business" do
      context "when allowing public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::BUSINESS_DESCRIPTION)

          biz = business(public_code_suggestions: :allowed)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when not allowing public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed::BUSINESS_DESCRIPTION)

          biz = business(public_code_suggestions: :blocked)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
