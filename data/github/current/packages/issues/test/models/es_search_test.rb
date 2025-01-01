# typed: true
# frozen_string_literal: true
require "test_helper"

class EsSearchTest < GitHub::TestCase

  context ".detect_type" do
    test "is:issue" do
      result = Issue::EsSearch.detect_type("is:issue")
      assert_equal "issue", result
    end

    test "is:pr" do
      result = Issue::EsSearch.detect_type("is:pr")
      assert_equal "pr", result
    end

    test "is:issue is:pr" do
      result = Issue::EsSearch.detect_type("is:issue is:pr")
      assert_nil result
    end

    test "is:open" do
      result = Issue::EsSearch.detect_type("is:open")
      assert_nil result
    end

    test "is:open is:issue" do
      result = Issue::EsSearch.detect_type("is:open is:issue")
      assert_equal "issue", result
    end

    test "type:issue" do
      result = Issue::EsSearch.detect_type("type:issue")
      assert_equal "issue", result
    end

    test "type:pr" do
      result = Issue::EsSearch.detect_type("type:pr")
      assert_equal "pr", result
    end

    test "type:issue type:pr" do
      result = Issue::EsSearch.detect_type("type:issue type:pr")
      assert_nil result
    end

    test "is:open type:issue" do
      result = Issue::EsSearch.detect_type("is:open is:issue")
      assert_equal "issue", result
    end
  end
end
