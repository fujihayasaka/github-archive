# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedInstallations::AuthorizationDetails::BuilderTest < GitHub::TestCase
  context ".build" do
    test "returns a V1 struct by default" do
      details = ScopedInstallations::AuthorizationDetails::Builder.build

      assert_kind_of(ScopedInstallations::AuthorizationDetails::PublicMethods, details)
      assert_instance_of(ScopedInstallations::AuthorizationDetails::Structs::V1, details)
    end

    test "returns a V2 struct for version 2" do
      details = ScopedInstallations::AuthorizationDetails::Builder.build(version: 2)

      assert_kind_of(ScopedInstallations::AuthorizationDetails::PublicMethods, details)
      assert_instance_of(ScopedInstallations::AuthorizationDetails::Structs::V2, details)
    end

    test "raises when an unsupported version is passed" do
      assert_raises_with_message(ArgumentError, "Unsupported authorization details version: 42") do
        ScopedInstallations::AuthorizationDetails::Builder.build(version: 42)
      end
    end
  end
end
