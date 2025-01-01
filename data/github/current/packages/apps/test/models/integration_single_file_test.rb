# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationSingleFileTest < GitHub::TestCase
  fixtures do
    version = create(:integration_version)
    @subject = IntegrationSingleFile.create(version: version, path: ".github/ISSUE_TEMPLATE.md")

    assert_predicate @subject, :valid?
  end

  context "validation" do
    test "version is required" do
      @subject.update(version: nil)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:version], "must exist"
    end

    test "path is required" do
      @subject.update(path: nil)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:path], "can't be blank"
    end

    test "path is unique to the version" do
      single_file = @subject.dup
      single_file.save

      refute_predicate single_file, :valid?
      assert_includes single_file.errors[:path], "has already been taken"
    end

    test "path is no more than 255 characters" do
      @subject.update(path: "t" * 256)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:path], "is too long (maximum is 255 characters)"
    end

    test "path cannot include invalid UTF-8 characters" do
      string_with_rtl_override = "path/with/rtl/override\u202e"
      @subject.update(path: string_with_rtl_override)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:path], "contains invalid characters"
    end

    test "path cannot include invalid UTF-8 character U202B" do
      string_with_rtl_override = "path/with/rtl/override\u202b"
      @subject.update(path: string_with_rtl_override)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:path], "contains invalid characters"
    end

    test "path cannot include invalid UTF-8 character U200F" do
      string_with_rtl_override = "path/with/rtl/override\u200f"
      @subject.update(path: string_with_rtl_override)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:path], "contains invalid characters"
    end
  end
end
