# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Failbot middleware and rollup" do # rubocop:disable RSpec/DescribeClass
  before do
    Failbot.reset!
    Failbot.setup(
      { "FAILBOT_BACKEND" => "memory" }, { "shared" => "Default Context" }
    )
    # Re-register the custom rollup after setup (setup calls use_default_rollup)
    load Rails.root.join("config/initializers/failbot.rb")
  end

  def last_report
    Failbot.backend.reports.last
  end

  describe "Failbot.rollup" do
    let(:error) { ArgumentError.new("test") }

    it "uses transaction-based rollup when transaction is in context" do
      transaction = "RouteClass"
      expected_rollup = Digest::SHA256.hexdigest("#{error.class}#{transaction}")

      Failbot.push(transaction: transaction) do
        Failbot.report(error)
      end

      expect(last_report["rollup"]).to eq(expected_rollup)
    end

    it "falls back to default rollup when no transaction is set" do
      err = begin
        raise ArgumentError, "test"
      rescue ArgumentError => e
        e
      end

      expected_rollup = Failbot.default_rollup(err)

      Failbot.report(err)

      expect(last_report["rollup"]).to eq(expected_rollup)
    end

    it "preserves an explicitly provided rollup" do
      explicit_rollup = "custom_rollup_value"

      Failbot.push(transaction: "SomeRoute") do
        Failbot.report(error, { rollup: explicit_rollup })
      end

      expect(last_report["rollup"]).to eq(explicit_rollup)
    end

    it "uses transaction from Dependabot::Exceptions.push" do
      transaction = "MyCoachRoute"
      expected_rollup = Digest::SHA256.hexdigest("#{error.class}#{transaction}")

      Dependabot::Exceptions.push(transaction: transaction) do
        Dependabot::Exceptions.report(error)
      end

      expect(last_report["rollup"]).to eq(expected_rollup)
    end

    it "falls back to default rollup via Dependabot::Exceptions without transaction" do
      err = begin
        raise ArgumentError, "test"
      rescue ArgumentError => e
        e
      end

      expected_rollup = Failbot.default_rollup(err)

      Dependabot::Exceptions.report(err)

      expect(last_report["rollup"]).to eq(expected_rollup)
    end
  end
end
