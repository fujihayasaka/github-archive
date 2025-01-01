# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module FlipperActorAdapters
    class RepositoryTest < GitHub::TestCase
      test "it returns expected flipper_id" do
        assert_equal "Repository:42", FlipperActorAdapters::Repository.new(42).flipper_id
      end
    end

    class OrganizationTest < GitHub::TestCase
      test "it returns expected flipper_id" do
        assert_equal "Organization:42", FlipperActorAdapters::Organization.new(42).flipper_id
      end
    end

    class BusinessTest < GitHub::TestCase
      test "it returns expected flipper_id" do
        assert_equal "Business:42", FlipperActorAdapters::Business.new(42).flipper_id
      end
    end
  end
end
