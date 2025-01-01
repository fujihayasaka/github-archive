# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module KV
    class KeyTransformerTest < GitHub::TestCase
      context ".new" do
        test "requires the old key pattern to capture `repository_id`" do
          assert_raises_with_message(ArgumentError, /must have a named capture called `repository_id`/) do
            KeyTransformer.new(old_key_pattern: /\Afoo\z/, new_key_template: "foo")
          end
        end

        test "requires the old key pattern to match the entire key" do
          assert_raises_with_message(ArgumentError, /must match the whole string/) do
            KeyTransformer.new(old_key_pattern: /repo(?<repository_id>\d+)\.foo/, new_key_template: "foo")
          end
        end

        test "requires the new key template variables to match the old key pattern's capture groups" do
          assert_raises_with_message(ArgumentError, /cannot contain template variables that don't correspond to named captures/) do
            KeyTransformer.new(
              old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
              new_key_template: "foo:%{foo_id}.bar:%{bar_id}",
            )
          end
        end
      end

      context "#new_key_and_repo_id" do
        test "transforms the key" do
          transformer = KeyTransformer.new(
            old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
            new_key_template: "foo:%{foo_id}"
          )

          assert_equal ["foo:1", 2], transformer.new_key_and_repo_id("repo2.foo1")
          assert_equal ["foo:4", 3], transformer.new_key_and_repo_id("repo3.foo4")
        end

        test "raises if the key doesn't match the old key pattern" do
          transformer = KeyTransformer.new(
            old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
            new_key_template: "foo:%{foo_id}"
          )

          assert_raises(KeyTransformer::UnexpectedKeyFormat) do
            transformer.new_key_and_repo_id("not a matching key!")
          end
        end
      end

      context "#transform" do
        test "transforms the key" do
          transformer = KeyTransformer.new(
            old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
            new_key_template: "foo:%{foo_id}"
          )

          assert_equal "foo:1", transformer.transform("repo2.foo1")
          assert_equal "foo:4", transformer.transform("repo3.foo4")
        end

        test "returns the key if it doesn't match the old key pattern" do
          transformer = KeyTransformer.new(
            old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
            new_key_template: "foo:%{foo_id}"
          )

          assert_equal "some-other-key", transformer.transform("some-other-key")
        end
      end

      context "#transform_prefix" do
        test "raises" do
          transformer = KeyTransformer.new(
            old_key_pattern: /\Arepo(?<repository_id>\d+)\.foo(?<foo_id>\d+)\z/,
            new_key_template: "foo:%{foo_id}"
          )

          assert_raises(NotImplementedError) do
            transformer.transform_prefix("foo")
          end
        end
      end
    end
  end
end
