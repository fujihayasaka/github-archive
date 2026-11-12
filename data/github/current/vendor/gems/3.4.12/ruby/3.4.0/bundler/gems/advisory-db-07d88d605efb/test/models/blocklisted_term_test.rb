# frozen_string_literal: true

require "test_helper"

class BlocklistedTermTest < ActiveSupport::TestCase
  test "requires a pattern" do
    blocklisted_term = build(:blocklisted_term, pattern: " ")

    refute blocklisted_term.valid?
  end

  test "ensures a valid regular expression" do
    blocklisted_term = build(:blocklisted_term, pattern: "/(foo/")

    refute blocklisted_term.valid?
  end

  test "accepts string patterns" do
    blocklisted_term = build(:blocklisted_term, pattern: "bar")

    assert blocklisted_term.valid?
  end

  test "accepts regular expression patterns" do
    blocklisted_term = build(:blocklisted_term, pattern: "/bar/")

    assert blocklisted_term.valid?
  end

  test "matches string patterns" do
    blocklisted_term = create(:blocklisted_term, pattern: "bar")

    assert blocklisted_term.match?("foo bar baz")
  end

  test "matches regular expression patterns" do
    blocklisted_term = create(:blocklisted_term, pattern: "/ba[rz]/")

    assert blocklisted_term.match?("foo bar baz")
  end

  test "matches string patterns on word boundaries" do
    blocklisted_term = create(:blocklisted_term, pattern: "bar")

    refute blocklisted_term.match?("foobarbaz")
  end

  test "matches string patterns with special character" do
    blocklisted_term = create(:blocklisted_term, pattern: "+bar+")

    assert blocklisted_term.match?("foo +bar+ baz")
  end

  test "matches string patterns with many special character" do
    blocklisted_term = create(:blocklisted_term, pattern: "+bar+")

    assert blocklisted_term.match?("foo++bar++baz")
  end

  test "matches string patterns starting/ending with special character" do
    blocklisted_term = create(:blocklisted_term, pattern: "+bar+")

    assert blocklisted_term.match?("+bar+")
  end

  test "matches regular expression patterns on word boundaries" do
    blocklisted_term = create(:blocklisted_term, pattern: "/ba[rz]/")

    refute blocklisted_term.match?("foobarbaz")
  end

  test "respects optional case-insenstivity" do
    cs_blocklisted_term = create(:blocklisted_term, pattern: "/ba[rz]/")
    ci_blocklisted_term = create(:blocklisted_term, pattern: "/ba[rz]/i")

    assert cs_blocklisted_term.match?("foo bar baz")
    assert ci_blocklisted_term.match?("foo bar baz")
    refute cs_blocklisted_term.match?("FOO BAR BAZ")
    assert ci_blocklisted_term.match?("FOO BAR BAZ")
  end
end
