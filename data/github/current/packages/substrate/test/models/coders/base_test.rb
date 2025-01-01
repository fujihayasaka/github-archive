# typed: true
# frozen_string_literal: true

require "test_helper"

class CodersBaseTest < GitHub::TestCase
  fixtures do
    Coders::Base.data_accessors(:name, :organization)
  end

  context ".data_accessors(*iaccessors)" do
    test "updates members to include reader methods" do
      readers = [:name, :organization]
      assert_equal readers, Coders::Base.members & readers, "data readers were not included"
    end

    test "updates members to include question mark methods" do
      questions = [:name?, :organization?]
      assert_equal questions, Coders::Base.members & questions, "question methods were not included"
    end

    test "updates members to includes writer methods" do
      writers = [:name=, :organization=]
      assert_equal writers, Coders::Base.members & writers, "data writer methods were not included"
    end

    test "adds instance reader methods" do
      test_coder = Coders::Base.new(name: "Octocat", organization: "GitHub")
      assert T.unsafe(test_coder).name == "Octocat", "name should match Octocat"
      assert T.unsafe(test_coder).organization == "GitHub", "organization should match GitHub"
    end

    test "adds instances question methods" do
      test_coder = Coders::Base.new(name: "Octocat", organization: "GitHub")
      assert T.unsafe(test_coder).name?, "name should be truthy"
      assert T.unsafe(test_coder).organization?, "organization should be truthy"
    end

    test "adds instances writer methods" do
      test_coder = Coders::Base.new
      T.unsafe(test_coder).name = "Octocat"
      T.unsafe(test_coder).organization = "GitHub"

      assert T.unsafe(test_coder).name == "Octocat", "name should be set"
      assert T.unsafe(test_coder).organization == "GitHub", "organization should be set"
    end
  end

  context "#to_h" do
    test "returns a hash with reader keys" do
      test_coder = Coders::Base.new(name: "Octocat", organization: "GitHub")
      assert_equal [:name, :organization], test_coder.to_h.keys, "hash keys include :name and :organization"
    end

    test "skips keys with nil values" do
      test_coder = Coders::Base.new(name: "Octocat")
      assert_equal({ name: "Octocat" }, test_coder.to_h, "skips nil values")
    end
  end
end
