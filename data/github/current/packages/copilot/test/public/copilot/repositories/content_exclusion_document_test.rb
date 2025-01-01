# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotRepositoriesContentExclusionDocument < GitHub::TestCase
  include CopilotTestHelper

  setup do
    @valid_policy = <<~POLICY
      - /secrets/*
      - /envs/*
    POLICY
  end

  def get_ignore_document(document, allow_text_based_rules: false)
    Copilot::Repositories::ContentExclusionDocument.new(document, allow_text_based_rules:)
  end

  def cache_key(string)
    "copilot:ignore:document:rules:#{Digest::SHA256.hexdigest(string)}:false"
  end

  context "#validate" do
    test "returns valid rules" do
      rules = get_ignore_document(@valid_policy).validate
      assert rules.ok?
    end

    test "we have an array of Rule objects" do
      rules = get_ignore_document(@valid_policy).validate
      assert rules.value!.all? { |rule| rule.is_a?(Copilot::ContentExclusion::Rule) }
    end

    test "fails with no paths given" do
      rules = get_ignore_document("test:").validate
      refute rules.ok?
      assert_equal "Error on line 1, column 1: Expecting an array of paths", rules.error.message
    end

    test "fails for nested objects" do
      rules = get_ignore_document("""
        - /folders/*
        - abc:
          - /folders/*
      """).validate
      refute rules.ok?
      assert_equal "Error on line 3, column 11: Expecting a path pattern", rules.error.message
    end

    test "works for json-like paths" do
      rules = get_ignore_document("['/my-folder/*']").validate
      assert rules.ok?
    end

    test "allows for comments" do
      rules = get_ignore_document("['/my-folder/*'] # my secrets are in this folder").validate
      assert rules.ok?
    end

    test "allows for blanks" do
      rules = get_ignore_document(<<~YAML).validate
      - #empty
      - value
      YAML
      assert rules.ok?
      assert_equal ["value"], rules.value!.flat_map(&:patterns)
    end

    context "path validations" do
      test "does not allow negated rules" do
        rules = get_ignore_document("['!my-folder/*']").validate
        refute rules.ok?
        assert_equal "Error on line 1, column 2: Negated patterns not supported", rules.error.message
      end

      test "allows for negated expressions" do
        rules = get_ignore_document("['!(a|b)']").validate
        assert rules.ok?
      end
    end
  end


  context "#rules" do
    test "gets the rules through the cache" do
      valid_rules = get_ignore_document(@valid_policy).validate.value { [] }

      Copilot.redis.set(cache_key(@valid_policy), valid_rules.to_json)

      rules = get_ignore_document(@valid_policy).rules

      assert_equal rules.length, 1
      assert_equal rules.first.patterns.length, 2
      valid_rules.each_with_index do |rule, index|
        assert_equal rule, rules[index]
      end
      assert_equal valid_rules, rules
    end

    test "gets rules when cache is empty and sets the cache" do
      valid_rules = get_ignore_document(@valid_policy).validate.value { [] }

      Copilot.redis.del(cache_key(@valid_policy))

      rules = get_ignore_document(@valid_policy).rules

      assert_equal rules.length, 1
      assert_equal rules.first.patterns.length, 2
      valid_rules.each_with_index do |rule, index|
        assert_equal rule, rules[index]
      end
      assert_equal valid_rules, rules

      # Check that the cache was set
      cache_rules = JSON.parse(Copilot.redis.get(cache_key(@valid_policy))).map { |rule| Copilot::ContentExclusion::Rule.from_hash(rule) }

      assert_equal valid_rules, cache_rules
      assert_equal rules, cache_rules
    end

    test "gets rules when cache returns an invalid value and resets the cache" do
      valid_rules = get_ignore_document(@valid_policy).validate.value { [] }

      Copilot.redis.set(cache_key(@valid_policy), "invalid json")

      rules = get_ignore_document(@valid_policy).rules

      assert_equal rules.length, 1
      assert_equal rules.first.patterns.length, 2
      valid_rules.each_with_index do |rule, index|
        assert_equal rule, rules[index]
      end
      assert_equal valid_rules, rules

      # Check that the cache was reset
      cache_rules = JSON.parse(Copilot.redis.get(cache_key(@valid_policy))).map { |rule| Copilot::ContentExclusion::Rule.from_hash(rule) }

      assert_equal valid_rules, cache_rules
      assert_equal rules, cache_rules
    end

    test "gets rules when the cache is not working" do
      valid_rules = get_ignore_document(@valid_policy).validate.value { [] }

      Copilot.redis.del(cache_key(@valid_policy))

      Copilot.redis.stubs(:get).raises(Redis::BaseError)

      rules = get_ignore_document(@valid_policy).rules

      assert_equal rules.length, 1
      assert_equal rules.first.patterns.length, 2
      valid_rules.each_with_index do |rule, index|
        assert_equal rule, rules[index]
      end
      assert_equal valid_rules, rules
    end
  end

  context "#all_scoped_rules" do
    test "returns an empty array as scopes arent relevant to repositories" do
      all_scoped_rules = get_ignore_document(@valid_policy).all_scoped_rules

      assert all_scoped_rules.empty?
    end
  end

  context "allow_text_based_rules" do
    test "should fail when allow_inclusions is false" do
      rules = get_ignore_document("[ifNoneMatch: [/abc/]]", allow_text_based_rules: false).validate
      refute rules.ok?
      assert_equal "Error on line 1, column 2: Expecting a path pattern", rules.error.message
    end

    test "works with inclusion rules" do
      rules = get_ignore_document("[ifNoneMatch: [/abc/]]", allow_text_based_rules: true).validate
      assert rules.ok?
      assert_equal ["/abc/"], rules.value!.flat_map(&:if_none_match)
    end

    test "fails if the keys are not valid regex" do
      rules = get_ignore_document("[ifNoneMatch: ['/[/']]", allow_text_based_rules: true).validate
      refute rules.ok?
      assert_equal "Error on line 1, column 16: Invalid regular expression: premature end of char-class: /\\/[\\//", rules.error.message
    end

    test "can support multiple keys per configuration entry" do
      rules = get_ignore_document(<<~YAML, allow_text_based_rules: true).validate
      - ifNoneMatch: [/abc/] # block the file if none of the patterns match
      - ifAnyMatch: [/def/] # at least one of the patterns must match to block the file
      - "**.md" # and block md files
      - ifAnyMatch: [/foo/, /bar/i]
      YAML
      assert rules.ok?
      rules = rules.value!
      assert_equal ["/abc/"], rules.flat_map(&:if_none_match)
      assert_equal ["/def/", "/foo/", "/bar/i"], rules.flat_map(&:if_any_match)
      assert_equal ["**.md"], rules.flat_map(&:patterns)
    end
  end
end
