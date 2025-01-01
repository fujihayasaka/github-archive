# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsDataAttributesTest < GitHub::TestCase
  test "it automatically applies memoized getters and setters" do
    user = User.new(id: 1)

    instance = T.unsafe(TestDataFixture.new)

    instance.name = "hello"
    assert_equal "hello", instance.name

    instance.user = user
    assert_equal user.object_id, instance.user.object_id
    assert_equal({ "_aj_globalid" => "gid://git-hub/User/1" }, instance.data[:user])
  end

  context "type:" do
    test "when an invalid type is given an error is thrown" do
      instance = T.unsafe(TestDataFixture.new)

      assert_raises Orchestration::Error do
        instance.user = Object.new
      end
    end

    test "when deserializing the wrong object it throws an error" do
      instance = T.unsafe(TestDataFixture.new({
        name: TestDataFixture.data_attributes[:user]&.serialize!(User.ghost)
      }))

      assert_raises Orchestration::Error do
        instance.user
      end
    end
  end

  context "Types::Boolean" do
    test "it validates the data type is a boolean" do
      instance = T.unsafe(TestDataFixture.new)

      instance.is_neat = true
      assert_equal true, instance.is_neat
    end
  end

  context "required:" do
    test "when writing nil values to required fields raises an error" do
      instance = T.unsafe(TestDataFixture.new)

      assert_raises Orchestration::Error do
        instance.user = nil
      end
    end

    test "when reading nil values to required fields raises an error" do
      instance = T.unsafe(TestDataFixture.new)
      assert_raises Orchestration::Error do
        instance.user
      end
    end

    test "reading and writing non required fields does not throw an error" do
      instance = T.unsafe(TestDataFixture.new({
        head_sha: "123abc"
      }))

      instance.head_sha = nil
      assert_nil instance.head_sha
    end
  end

  context "persisted:" do
    test "it allows preventing the persistence of a value and throws an error when utilized" do
      instance = T.unsafe(TestDataFixture.new)

      assert_raises Orchestration::Error do
        instance.large_user_data_blob
      end
    end

    test "it does not write to the data field if not persisted" do
      instance = T.unsafe(TestDataFixture.new)

      instance.large_user_data_blob = "this would be very large user content"
      assert_nil instance.data[:large_user_data_blob]
    end
  end

  context "persisted and required" do
    test "returns nil when not set and not persisted or required" do
      instance = T.unsafe(TestDataFixture.new)

      assert_nil instance.blah
    end
  end

  context "default:" do
    test "sets a default if passed a default parameter" do
      instance = T.unsafe(TestDataFixture.new)

      assert_equal instance.foo, :bar
    end

    test "overrides set default if passed an argument" do
      instance = T.unsafe(TestDataFixture.new)

      instance.foo = :baz
      assert_equal instance.foo, :baz
    end

    test "cannot invoke a setter or getter for an attribute with a nil default" do
      instance = T.unsafe(TestDataFixture.new)

      assert_raises Orchestration::Error do
        instance.bad_attr
      end

      assert_raises Orchestration::Error do
        instance.bad_attr = nil
      end
    end
  end

  class TestDataFixture
    include PullRequests::Orchestrations::DataAttributes

    data :name, String
    data :user, User
    data :head_sha, String, required: false
    data :large_user_data_blob, String, persisted: false
    data :is_neat, Types::Boolean
    data :foo, Symbol, default: :bar
    data :bad_attr, Symbol, default: nil
    data :blah, String, required: false, persisted: false

    attr_reader :data

    def initialize(data = {})
      @data = data
    end
  end
end
