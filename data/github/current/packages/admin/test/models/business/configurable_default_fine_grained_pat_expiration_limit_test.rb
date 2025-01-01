# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessConfigurableDefaultFineGrainedPatExpirationLimitTest < GitHub::TestCase
  test "sets default expiration after creation when FF enabled", feature_enabled: :set_default_fg_pat_expr_limit_on_creation  do
    assert_difference(Configuration::Entry.where(name: Configurable::PersonalAccessTokenExpirationLimit::FG_PAT_KEY), 1) do
      biz = create :business
      assert_equal Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT, biz.fine_grained_personal_access_token_expiration_limit
    end
  end

  test "does not set default expiration after creation when FF disabled", feature_disabled: :set_default_fg_pat_expr_limit_on_creation do
    assert_no_difference Configuration::Entry.where(name: Configurable::PersonalAccessTokenExpirationLimit::FG_PAT_KEY) do
      create :business
    end
  end
end
