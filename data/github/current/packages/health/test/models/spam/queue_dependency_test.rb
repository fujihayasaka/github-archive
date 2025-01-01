# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamQueueDependencyTest < GitHub::TestCase
  context ".mark_login_tainted" do
    test "marks a login as tainted" do
      Spam.mark_login_tainted("harpua")

      assert Spam.login_is_tainted?("harpua")
    end
  end

  context ".login_is_tainted?" do
    test "returns true when login is tainted" do
      Spam.mark_login_tainted("harpua")

      assert Spam.login_is_tainted?("harpua")
    end

    test "returns false when login is not tainted" do
      refute Spam.login_is_tainted?("wilson")
    end
  end

  context ".clear_tainted_login" do
    test "clears the tainted login" do
      Spam.mark_login_tainted("harpua")

      assert Spam.login_is_tainted?("harpua")

      Spam.clear_tainted_login("harpua")

      refute Spam.login_is_tainted?("harpua")
    end
  end
end
