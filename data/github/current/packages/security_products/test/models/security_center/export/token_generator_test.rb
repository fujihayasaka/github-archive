# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Export
    class TokenGeneratorTest < GitHub::TestCase
      test "returns same output for same input" do
        user = create(:user)
        organization = create(:organization)
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "risk", requested_at:, start_date: Date.current, end_date: Date.current)
        t2 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "risk", requested_at:, start_date: Date.current, end_date: Date.current)

        assert_equal t1, t2
      end

      test "returns different output for different users" do
        u1 = create(:user)
        u2 = create(:user)
        organization = create(:organization)
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user: u1, scope: organization, query: "foobar", feature_type: "risk", requested_at:, start_date: Date.current, end_date: Date.current)
        t2 = TokenGenerator.create_token(user: u2, scope: organization, query: "foobar", feature_type: "risk", requested_at:, start_date: Date.current, end_date: Date.current)

        refute_equal t1, t2
      end

      test "returns different output for different organization scopes" do
        user = create(:user)
        o1 = create(:organization)
        o2 = create(:organization)
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user:, scope: o1, query: "foobar", feature_type: "risk", requested_at:)
        t2 = TokenGenerator.create_token(user:, scope: o2, query: "foobar", feature_type: "risk", requested_at:)

        refute_equal t1, t2
      end

      test "returns different output for different business scopes", skip_enterprise: true do
        user = create(:user)
        b1 = create(:business)
        b2 = create(:business)
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user:, scope: b1, query: "foobar", feature_type: "risk", requested_at:)
        t2 = TokenGenerator.create_token(user:, scope: b2, query: "foobar", feature_type: "risk", requested_at:)

        refute_equal t1, t2
      end

      test "returns different output for an org and a business with the same name", skip_enterprise: true do
        user = create(:user)
        b = create(:business, name: "my-scope")
        o = create(:organization, login: "my-scope")
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user:, scope: b, query: "foobar", feature_type: "risk", requested_at:)
        t2 = TokenGenerator.create_token(user:, scope: o, query: "foobar", feature_type: "risk", requested_at:)

        refute_equal t1, t2
      end

      test "returns different output for different queries" do
        user = create(:user)
        organization = create(:organization)
        requested_at = Time.now

        t1 = TokenGenerator.create_token(user:, scope: organization, query: "foo", feature_type: "risk", requested_at:)
        t2 = TokenGenerator.create_token(user:, scope: organization, query: "bar", feature_type: "risk", requested_at:)

        refute_equal t1, t2
      end

      test "returns different output for different requested_at" do
        user = create(:user)
        organization = create(:organization)

        t1 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "risk", requested_at: Time.now)
        t2 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "risk", requested_at: Time.new(Time.now - 1.minute.ago))

        refute_equal t1, t2
      end

      test "raises error for overview_dashboard if start_date or end_date isn't defined" do
        user = create(:user)
        organization = create(:organization)
        requested_at = Time.now

        assert_raises_with_message(RuntimeError, "Start and end date must be defined") do
          t1 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "overview_dashboard", requested_at:, start_date: Date.current)
        end

        assert_raises_with_message(RuntimeError, "Start and end date must be defined") do
          t2 = TokenGenerator.create_token(user:, scope: organization, query: "foobar", feature_type: "overview_dashboard", requested_at:, end_date: Date.current)
        end
      end
    end
  end
end
