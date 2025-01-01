# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::QueryTest < GitHub::TestCase
  test "content type is set" do
    TestClass.expects(:contentful_request).with(has_entry(:content_type, TestClass.content_type))

    TestClass.query
  end

  test "select clause with array of symbols" do
    TestClass.expects(:contentful_request).with(has_entry(:select, "fields.hello,fields.world"))

    TestClass.query(select: [:hello, :world])
  end

  test "select clause with :fields" do
    TestClass.expects(:contentful_request).with(has_entry(:select, "fields,fields.other"))

    TestClass.query(select: [:fields, :other])
  end

  test "select clause with single symbol" do
    TestClass.expects(:contentful_request).with(has_entry(:select, "fields.hello"))

    TestClass.query(select: :hello)
  end

  test "select clause with raw string" do
    TestClass.expects(:contentful_request).with(has_entry(:select, "fields.hello,fields.world"))

    TestClass.query(select: "fields.hello,fields.world")
  end

  test "select clause isn't provided" do
    TestClass.expects(:contentful_request).with(Not(has_key(:select)))

    TestClass.query
  end

  test "filtering by fields" do
    TestClass.expects(:contentful_request).with(has_entry("fields.hello", "world"))

    TestClass.query(fields: { hello: "world" })
  end

  test "filtering fields with multiple values" do
    TestClass.expects(:contentful_request).with(has_entry("fields.hello[in]", "world,universe"))

    TestClass.query(fields: { hello: %w[world universe] })
  end

  test "filtering fields with operators" do
    TestClass.expects(:contentful_request).with(has_entries({
      "fields.publishedAt[lt]" => Date.today.iso8601,
      "fields.hello[in]" => "world,universe",
      "fields.hello[exists]" => "true",
    }))

    TestClass.query(fields: {
      publishedAt: { lt: Date.today.iso8601 },
      hello: { in: %w[world universe], exists: true }
    })
  end

  test "filtering empty fields" do
    TestClass.expects(:contentful_request).with(Not(has_key(:fields)))

    TestClass.query(fields: {})
  end

  test "including other params in query" do
    TestClass.expects(:contentful_request).with(has_entries({
      :skip => 3,
      :order => "sys.createdAt",
      "fields.hello" => "world",
    }))

    TestClass.query(:skip => 3, :order => "sys.createdAt", "fields.hello" => "world")
  end

  test "snake case keys are converted to camel case by default" do
    TestClass.expects(:contentful_request).with(has_entries({
      :select => "fields.helloWorld",
      "fields.helloWorld" => "world",
    }))

    TestClass.query(fields: { hello_world: "world" }, select: :hello_world)
  end

  test "camel casing is optional" do
    TestClass.expects(:contentful_request).with(has_entries({
      :select => "fields.hello_world",
      "fields.hello_world" => "world",
    }))

    TestClass.query(fields: { hello_world: "world" }, select: :hello_world, camelize_fields: false)
  end

  test "nothing returned from contentful" do
    TestClass.expects(:contentful_request).returns(nil)

    assert_equal [], TestClass.query
  end

  class TestClass
    include Site::Contentful::Query

    def self.content_type
      "test"
    end

    def self.contentful_request(query_params)
      []
    end
  end
end
