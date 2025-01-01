# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Email
  class AuthorUserTest < GitHub::TestCase
    fixtures { @user = create(:user) }
    setup { @author = AuthorUser.new(user: @user) }

    test "#profile_name" do
      assert_equal @user.safe_profile_name, @author.profile_name
    end
  end
end
