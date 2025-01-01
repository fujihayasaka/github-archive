# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamConditionalTest < GitHub::TestCase
  setup do
    @condition_hash = {
      actions: "flag queue",
      hard_flag: false,
      message: "was naughty",
      conditions: [
        {
          attribute_name: "login",
          pattern: /fruit/i,
        },
        {
          attribute_name: "login",
          pattern: /fly/,
        },
        {
          "attribute_name" => "last_ip",
          "pattern" => /71.40.145/,
        },
      ],
    }
    @spammy_user = create :user, login: "fruitfly", last_ip: "71.40.145.32"
    @almost_spammy_user1 = create :user, login: "flyfruit", last_ip: "1.2.3.4"
    @almost_spammy_user2 = create :user, login: "dogfly", last_ip: "71.40.145.32"
    @user = create :user, login: "bangarang"
  end

  context "#initialize" do
    test "properly handles a hash as initializer" do
      conditional = Spam::Conditional.new @condition_hash
      assert_equal @condition_hash[:message], conditional.message
      assert_equal 3, conditional.conditions.count
    end

    test "properly handles JSON String as initializer" do
      conditional = Spam::Conditional.new @condition_hash.to_json
      assert_equal @condition_hash[:message], conditional.message
      assert_equal 3, conditional.conditions.count
    end
  end

  context "#matches?" do
    test "matches a matching record" do
      conditional = Spam::Conditional.new @condition_hash
      assert conditional.matches? @spammy_user
    end

    test "doesn't match non-matching records" do
      conditional = Spam::Conditional.new @condition_hash
      refute conditional.matches? @user
      refute conditional.matches? @almost_spammy_user1
      refute conditional.matches? @almost_spammy_user2
    end
  end

  context "#dump_to_json" do
    test "can re-create itself as a JSON String" do
      conditional = Spam::Conditional.new @condition_hash
      cond2 = conditional.class.new(conditional.dump_to_json)
      assert_equal cond2.dump_to_json, conditional.dump_to_json
    end
  end
end
