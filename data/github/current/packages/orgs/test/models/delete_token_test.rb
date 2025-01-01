# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteTokenTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, :minimal, owner: @user
  end

  test "validates token" do
    assert token = DeleteToken.generate(@user, @repo)
    assert  DeleteToken.valid?(@user, @repo, token)
    assert !DeleteToken.valid?(@user, @repo, "monkey")
  end

  test "verifies token" do
    assert token = DeleteToken.generate(@user, @repo)
    assert DeleteToken.verify!(@user, @repo, token)
    assert_raises DeleteToken::DangerZone do
      DeleteToken.verify! @user, @repo, "monkey"
    end
  end
end
