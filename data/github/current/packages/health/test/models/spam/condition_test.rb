# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamConditionTest < GitHub::TestCase
  setup do
    @condition_hash = {
      property: "login",
      pattern: /fruit/i,
    }
    @destructive_hash = {
      property: "destroy",
      pattern: /pwned/i,
    }
    @spammy_user = create :user, login: "fruitfly"
    @user        = create :user, login: "bangarang"
  end

  context "#initialize" do
    test "properly handles a hash as initializer" do
      condition = Spam::Condition.new @condition_hash
      assert_equal @condition_hash[:property], condition.property
      assert_equal @condition_hash[:pattern], condition.pattern
    end

    test "properly handles JSON String as initializer" do
      condition = Spam::Condition.new @condition_hash.to_json
      assert_equal @condition_hash[:property], condition.property
      # Have to stringify the original hash, because JSON will #to_s it
      assert_equal @condition_hash[:pattern].to_s, condition.pattern
    end
  end

  context "has_allowed_method?" do
    test "prevents calling parent instance methods" do
      condition = Spam::Condition.new @destructive_hash
      refute condition.matches? @user
      assert @user.reload
    end
  end

  context "#matches?" do
    test "matches a matching record" do
      condition = Spam::Condition.new @condition_hash
      assert condition.matches? @spammy_user
    end

    test "doesn't match a non-matching record" do
      condition = Spam::Condition.new @condition_hash
      refute condition.matches? @user
    end
  end

  context "#dump_to_json" do
    test "can re-create itself as a JSON String" do
      condition = Spam::Condition.new @condition_hash
      cond2 = condition.class.new(condition.dump_to_json)
      assert_equal cond2.dump_to_json, condition.dump_to_json
    end
  end
end
