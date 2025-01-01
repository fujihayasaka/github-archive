# typed: true
# frozen_string_literal: true
require "test_helper"

class TradeControlsNullComplianceTest < GitHub::TestCase
  def self.exposes_consistent_interface(subject)
    test "responds to violation?" do
      assert subject.respond_to? :violation?
    end

    test "#reason is symbol/string" do
      assert subject.reason.kind_of?(String) ||
          subject.reason.kind_of?(Symbol)
    end

    test "#to_hydro is a Hash" do
      assert_kind_of Hash, subject.to_hydro
    end
  end

  exposes_consistent_interface TradeControls::NullCompliance.new
end
