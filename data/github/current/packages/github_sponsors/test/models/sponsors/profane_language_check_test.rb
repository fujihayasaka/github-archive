# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsProfaneLanguageCheckTest < GitHub::TestCase
  def run
    Sponsors::ProfaneLanguageCheck.stub_const(:BLOCKED_TERMS, %w(road bubble plant)) do
      super
    end
  end

  context "#call" do
    test "returns true for a blocked term" do
      assert Sponsors::ProfaneLanguageCheck.call("road")
    end

    test "returns false for non blocked strings" do
      refute Sponsors::ProfaneLanguageCheck.call("berry")
    end

    test "returns true for a string that contains a blocked term" do
      assert Sponsors::ProfaneLanguageCheck.call("flasdjfbubbleiuglsj")
    end

    test "returns true for matching strings regardless of casing" do
      assert Sponsors::ProfaneLanguageCheck.call("PLANT")
      assert Sponsors::ProfaneLanguageCheck.call("pLaNt")
      assert Sponsors::ProfaneLanguageCheck.call("asdfPlantjfig")
    end
  end
end
