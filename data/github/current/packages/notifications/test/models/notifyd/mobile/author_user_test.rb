# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Mobile
  class MobileAuthorUserTest < GitHub::TestCase
    fixtures { @user = create(:user) }
    setup { @author = AuthorUser.new(user: @user) }

    test "#avatar_url" do
      assert_equal "http://alambic.github.test/avatars/u/#{@user.id}?b=1&v=2", @author.avatar_url
    end

    test "#profile_name" do
      assert_equal @user.safe_profile_name, @author.profile_name
    end

    test "#username" do
      assert_equal @user.display_login, @author.username
    end
  end
end
