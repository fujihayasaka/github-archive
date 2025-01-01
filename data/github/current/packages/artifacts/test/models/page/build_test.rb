# typed: true
# frozen_string_literal: true

require "test_helper"

class PageBuildTest < GitHub::TestCase
  fixtures do
    @serialization_attributes = {
      pusher_id: 1,
      commit: "commit",
      status: "built",
      error: "error",
      backtrace: "backtrace",
      duration: 1,
    }
  end

  context "#raw_data" do
    test "answers coder for raw data by default" do
      page_build = Page::Build.new
      assert_instance_of Coders::Page::BuildCoder, page_build.raw_data
    end

    test "answers serialized attributes" do
      proof = Coders::Page::BuildCoder.new @serialization_attributes
      page_build = create :page_build, **@serialization_attributes

      assert_equal proof.to_h, page_build.raw_data.to_h
    end
  end

  test "writes to both #raw_data and AR attributes" do
    page_build = create :page_build, **@serialization_attributes
    page_build.save!

    values = T.must(Page::Build.where(id: page_build.id).first).attributes
    @serialization_attributes.each do |attribute, expected|
      assert_equal expected, values[attribute.to_s],
        "Expected the value of #{attribute} to be saved to the database."
    end
  end
end
