# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessConfigurableDefaultFineGrainedPatExpirationLimitTest < GitHub::TestCase
  test "sets default expiration after creation" do
    assert_difference(Configuration::Entry.where(name: Configurable::PersonalAccessTokenExpirationLimit::FG_PAT_KEY), 1) do
      biz = create :business
      assert_equal Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT, biz.fine_grained_personal_access_token_expiration_limit
    end
  end
end
