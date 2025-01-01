# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsManualComplianceTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @compliance = TradeControls::ManualCompliance.new(actor: @user)
  end

  test "responds to violation?" do
    assert @compliance.respond_to? :violation?
  end

  test "#reason is symbol/string" do
    assert @compliance.reason.kind_of?(String) ||
      @compliance.reason.kind_of?(Symbol)
  end

  test "#to_hydro is a Hash" do
    assert_kind_of Hash, @compliance.to_hydro
  end

  test "#violation? is always true" do
    assert_predicate @compliance, :violation?
  end

  test "#to_hydro only includes actor and reason" do
    hydro = @compliance.to_hydro

    # Note, for manual compliance we don't expect location/region/country to be set since it's effectively an "override" and location is irrelevant in this case (similar to our threshold compliance)
    assert_equal 2, hydro.length
    hydro.assert_valid_keys(:actor, :reason)
  end
end
