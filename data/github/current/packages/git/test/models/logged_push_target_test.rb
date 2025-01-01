# typed: true
# frozen_string_literal: true

require "test_helper"

class LoggedPushTargetTest < GitHub::TestCase
  fixtures do
    @before  = "0123456789012345678901234567890123456789"
    @after   = "fedcba9876fedcba9876fedcba9876fedcba9876"
    @empty   = "0000000000000000000000000000000000000000"

  end

  setup do
    @created = LoggedPushTarget.new("refs/heads/master", @empty,  @after)
    @deleted = LoggedPushTarget.new("refs/heads/master", @before, @empty)
  end

  context ".parse_reflog_line" do
    test "parses a line of secondary (squashed) pushlog output" do
      target = LoggedPushTarget.parse_reflog_line("  refs/heads/other #{@before} #{@after}\n")
      assert_equal "refs/heads/other", target.ref
      assert_equal @before,            target.before
      assert_equal @after,             target.after
    end
  end

  test "is created if the before OID is 'empty'" do
    assert @created.created?
    refute @created.deleted?
  end

  test "is deleted if the after OID is 'empty'" do
    refute @deleted.created?
    assert @deleted.deleted?
  end
end
