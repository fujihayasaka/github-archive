# typed: false
# frozen_string_literal: true

require "test_helper"

class ConditionalAccessResultTest < GitHub::TestCase

  def conditional_access_result(resource: :r, policies: nil, safe_request_method: true)
    policies ||= Hash[
      :a, Hash[:private, :unsatisfied],
      :b, Hash[:private, :satisfied],
      :c, Hash[:private, :inapplicable],
      :d, Hash[:private, :unenforceable],
      :e, Hash[:private, :unsatisfied],
      :f, Hash[:private, :satisfied],
      :g, Hash[:private, :inapplicable],
      :h, Hash[:private, :unenforceable]
    ]

    @result ||= ConditionalAccess::Result::new(resource, policies, safe_request_method: safe_request_method)
  end

  context "constructor" do
    test "raises on nil resource" do
      e = assert_raises ArgumentError do
        ConditionalAccess::Result::new(nil, Hash[])
      end
      assert_equal "resource cannot be nil", e.message
    end

    test "raises on empty policies hash" do
      e = assert_raises ArgumentError do
        ConditionalAccess::Result::new(:a, Hash[])
      end
      assert_equal "the policies hash cannot be empty", e.message
    end
  end

  Hash[
    :unsatisfied, [:a, :e],
    :satisfied, [:b, :f],
    :inapplicable, [:c, :g],
    :unenforceable, [:d, :h]
  ].each do |outcome, expected|
    test "can get list of #{outcome} policies" do
      assert_equal expected, conditional_access_result.send(outcome.to_sym)
    end
  end

  test "can get list of authorized policies" do
    assert_equal [:b, :c, :d, :f, :g, :h], conditional_access_result.authorized.keys
  end

  context "authorized?" do
    test "authorized? returns false and logs error when authorized is an array" do
      conditional_access_result.stubs(:authorized).returns([])

      GitHub.dogstats.expects(:count).with("cap.filter.result.authorized.error", 1, tags: ["authorized:Array"])

      assert_not conditional_access_result.authorized?
    end

    test "authorized? returns true when authorized keys match policies keys" do
      conditional_access_result.stubs(:authorized).returns({ a: :satisfied, b: :satisfied, c: :satisfied, d: :satisfied, e: :satisfied, f: :satisfied, g: :satisfied, h: :satisfied })

      assert conditional_access_result.authorized?
    end

    test "authorized? returns false when authorized keys do not match policies keys" do
      conditional_access_result.stubs(:authorized).returns({ a: :satisfied })

      assert_not conditional_access_result.authorized?
    end
  end

  context "when resource is a repository" do
    test "authorize if internal visibility matches satisfied policy visibility" do
      repo = create(:internal_repository)
      result = conditional_access_result(
        resource: repo,
        policies: { saml: { private: :unsatisfied, internal: :satisfied } },
        safe_request_method: true
      )

      assert result.authorized?
    end

    test "authorize if private visibility matches satisfied policy visibility" do
      repo = create(:private_repository)
      result = conditional_access_result(
        resource: repo,
        policies: { saml: { private: :satisfied, internal: :unsatisfied } },
        safe_request_method: true
      )

      assert result.authorized?
    end

    test "authorize if public visibility" do
      repo = create(:repository)
      result = conditional_access_result(
        resource: repo,
        policies: { saml: { private: :unsatisfied, internal: :unsatisfied, public: :satisfied } },
        safe_request_method: true
      )

      assert result.authorized?
    end
  end
end
