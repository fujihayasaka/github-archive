# typed: true
# frozen_string_literal: true

require "test_helper"

class BotHydratableTest < GitHub::TestCase
  class FakeAbilityDelegate
    include ActiveModel::Model
    include BotHydratable

    attr_accessor :ability_delegate_owner
  end

  class FakeAbilityDelegateOwner
    include ActiveModel::Model
    attr_accessor :bot
  end

  class FakeBot
    include Botable
  end

  class ImproperAbilityDelegate
    include ActiveModel::Model
    include BotHydratable
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @subject = FakeAbilityDelegate.new
  end

  context "#bot" do
    test "returns nothing if the ability delegate owner isn't set" do
      assert_nil @subject.ability_delegate_owner
      assert_nil @subject.bot
    end

    test "returns the bot with the subject as the ability delegate" do
      ability_delegate_owner = FakeAbilityDelegateOwner.new(bot: FakeBot.new)
      @subject.ability_delegate_owner = ability_delegate_owner

      assert_equal ability_delegate_owner.bot, @subject.bot
      assert_equal ability_delegate_owner.bot.ability_delegate, @subject
    end
  end

  context "#ability_delegate_owner" do
    test "#ability_delegate_owner raises an error if not redefined" do
      assert_raises NotImplementedError do
        ImproperAbilityDelegate.new.ability_delegate_owner
      end
    end
  end
end
