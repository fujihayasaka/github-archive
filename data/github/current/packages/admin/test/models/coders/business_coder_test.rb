# typed: true
# frozen_string_literal: true

require "test_helper"

class CodersBusinessCoderTest < GitHub::TestCase
  context "#completed_onboarding_tasks" do
    test "answers [] by default" do
      subject = Coders::BusinessCoder.new

      assert_equal [], subject.completed_onboarding_tasks
    end

    test "answers array of entries when set" do
      entries = [:task1, :task2]
      subject = Coders::BusinessCoder.new
      T.unsafe(subject).completed_onboarding_tasks = entries

      assert_equal entries, subject.completed_onboarding_tasks
    end
  end
end
