# typed: true
# frozen_string_literal: true

require "test_helper"

class CodersMultiReadWriterTest < GitHub::TestCase
  FakeDataSource = Struct.new(:attr1, :attr2, :attr3)

  setup do
    @source1 = FakeDataSource.new("first source attr1", nil, nil)
    @source2 = FakeDataSource.new("second source attr1", "second source attr2", nil)
    @multi_read_writer = Coders::MultiReadWriter.new(
      sources:    [@source1, @source2],
      attributes: [:attr1, :attr2, :attr3],
    )
  end

  test "it reads from both sources" do
    assert_equal @source1.attr1, @multi_read_writer.attr1
    assert_equal @source2.attr2, @multi_read_writer.attr2
    assert_nil @multi_read_writer.attr3
  end

  test "it questions both sources" do
    assert_predicate @multi_read_writer, :attr1?
    assert_predicate @multi_read_writer, :attr2?
    refute_predicate @multi_read_writer, :attr3?
  end

  test "it writes to both sources" do
    new_attr1 = "dual source attr1"
    @multi_read_writer.attr1 = new_attr1
    assert_equal new_attr1, @source1.attr1
    assert_equal new_attr1, @source2.attr1
  end

  test "it only adds methods for the given attributes" do
    refute @multi_read_writer.respond_to?(:attr100),
      "MultiReadWriter should only respond to methods defined in the attributes parameter"
  end
end
