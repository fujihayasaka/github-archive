# typed: true
# frozen_string_literal: true

require "test_helper"

class ProtectedBranch::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = %w(
      contents
    )

    assert_equal expected_public_subject_types, ProtectedBranch::Resources::PUBLIC_SUBJECT_TYPES

    branch = ProtectedBranch.new
    expected_public_subject_types.each do |st|
      assert branch.resources.respond_to?(st.to_sym), "protected branch resources should include #{st}"
    end
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "ProtectedBranch", ProtectedBranch::Resources::ABILITY_TYPE_PREFIX
  end
end
