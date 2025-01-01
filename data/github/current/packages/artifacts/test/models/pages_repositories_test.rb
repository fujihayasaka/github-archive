# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class PagesRepositoriesTest < GitHub::TestCase
    fixtures do
      @pages_user = create(:user, login: "RudyTheDeveloper") # Need a name that's not all downcased.
      @pages_repo = create(:repository, owner: @pages_user, from_example: :pages)
      @page       = @pages_repo.create_page
    end
    setup do

    end

    test "finds user pages repo for pages_host_name_v1 only" do
      @user_pages_repo = create(:repository, owner: @pages_user, name: "#{@pages_user.login}.#{GitHub.pages_host_name_v1}")
      @user_pages_repo.create_page

      assert_equal @user_pages_repo.id, @pages_user.async_user_pages_repo.sync&.id
    end

    test "finds user pages repo for pages_host_name_v2 only" do
      @user_pages_repo = create(:repository, owner: @pages_user, name: "#{@pages_user.login}.#{GitHub.pages_host_name_v2}")

      assert_equal @user_pages_repo.id, @pages_user.async_user_pages_repo.sync&.id
    end

    test "finds user pages repo for pages_host_name_v2 when both exist" do
      @user_pages_repo_v1 = create(:repository, owner: @pages_user, name: "#{@pages_user.login}.#{GitHub.pages_host_name_v1}")
      @user_pages_repo_v2 = create(:repository, owner: @pages_user, name: "#{@pages_user.login}.#{GitHub.pages_host_name_v2}")

      assert_equal @user_pages_repo_v2.id, @pages_user.async_user_pages_repo.sync&.id
    end
  end
end
