# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicyTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring an organization" do
      test "does not create a button" do
        GitHub::Menu::ButtonComponent.expects(:new).never

        org = organization(public_code_suggestions: :allowed)
        Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: org).component
      end
    end

    context "when configuring a business" do
      context "when there is no policy for public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy::DESCRIPTION, name: "copilot_public_code_suggestions")

          biz = business(public_code_suggestions: :no_policy)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: biz).component
        end
      end

      context "when there is a policy for public code suggestions" do
        test "creates a button with the correct attributes" do
          expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy::DESCRIPTION, name: "copilot_public_code_suggestions")

          biz = business(public_code_suggestions: :allowed)
          Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: biz).component
        end
      end
    end
  end

  context "#to_h" do
    context "when configuring an organization" do
      test "returns nil" do
        org = organization(public_code_suggestions: :allowed)
        assert_nil Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: org).to_h
      end
    end

    context "when configuring a business" do
      context "when there is no policy for public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy::DESCRIPTION)

          biz = business(public_code_suggestions: :no_policy)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end

      context "when there is a policy for public code suggestions" do
        test "returns the correct options" do
          expected = expected_hash(checked: false, description: Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy::DESCRIPTION)

          biz = business(public_code_suggestions: :allowed)
          hash = Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
