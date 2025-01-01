# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative("../test_helpers")

class Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicyTest < GitHub::TestCase
  include Copilot::Policies::MenuItems::TestHelpers

  context "#component" do
    context "when configuring a business" do
      test "does not render for a standalone business" do
        GitHub::Menu::ButtonComponent.expects(:new).never
        Copilot::Policies::MenuItems::Base.any_instance.stubs(:standalone_business?).returns(true)

        biz = business

        Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy.new(copilot_configurable: biz).component
      end

      test "renders a checked component for a non-standalone business when set to no policy" do
        expect_component_attrs(checked: true, description: Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy::DESCRIPTION, name: "copilot_telemetry_aggregation")

        biz = business(usage_telemetry_api: :no_policy)
        Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy.new(copilot_configurable: biz).component
      end

      test "renders an unchecked component for a non-standalone business when not set to no policy" do
        expect_component_attrs(checked: false, description: Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy::DESCRIPTION, name: "copilot_telemetry_aggregation")

        biz = business(usage_telemetry_api: :disabled)
        Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy.new(copilot_configurable: biz).component
      end
    end
  end

  context "#to_h" do
    context "when configuring an business" do
      context "when set to no policy" do
        test "returns the correct options" do
          expected = expected_hash(checked: true, description: Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy::DESCRIPTION)

          biz = business(usage_telemetry_api: :no_policy)
          hash = Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy.new(copilot_configurable: biz).to_h
          assert_equal expected, hash
        end
      end
    end
  end
end if GitHub.copilot_enabled?
