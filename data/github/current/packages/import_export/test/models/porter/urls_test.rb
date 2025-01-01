# typed: true
# frozen_string_literal: true

require "test_helper"

class PorterUrlsTest < GitHub::TestCase
  fixtures do
    @user = create(
      :user,
      login: "saw-the-light",
    )

    @repo = create(
      :repository,
      name:  "not-svn-anymore",
      owner: @user,
    )
  end

  setup do
    @url_helper = Object.new.extend(Porter::Urls)

    GitHub.stubs(:porter_url_template).returns(
      "http://import2.test/something/{owner}/{repository}/{id}{.format}",
    )

    GitHub.stubs(:porter_repository_admin_url_template).returns(
      "http://import2.test/admin/repository/{owner}/{repository}" \
      "/{id}{.format}",
    )

    GitHub.stubs(:porter_user_admin_url_template).returns(
      "http://import2.test/admin/user/{login}/{id}{.format}",
    )
  end

  test "#porter_url" do
    url = @url_helper.porter_url(repository: @repo)

    assert_equal(
      "http://import2.test/something/saw-the-light/not-svn-anymore" \
      "/#{@repo.id}",
      url,
    )
  end

  test "#porter_api_url" do
    url = @url_helper.porter_api_base_url(repository: @repo)

    assert_equal(
      "http://import2.test/something/saw-the-light/not-svn-anymore" \
      "/#{@repo.id}",
      url,
    )
  end

  test "#porter_admin_repository_url" do
    url = @url_helper.porter_admin_repository_url(repository: @repo)

    assert_equal(
      "http://import2.test/admin/repository/saw-the-light/not-svn-anymore" \
      "/#{@repo.id}",
      url,
    )
  end

  test "#porter_admin_repository_url :json => true" do
    url = @url_helper.porter_admin_repository_url(
      repository: @repo,
      options:    { json: true },
    )

    assert_equal(
      "http://import2.test/admin/repository/saw-the-light/not-svn-anymore" \
      "/#{@repo.id}.json",
      url,
    )
  end

  test "#porter_admin_user_url" do
    url = @url_helper.porter_admin_user_url(user: @user)

    assert_equal(
      "http://import2.test/admin/user/saw-the-light/#{@user.id}",
      url,
    )
  end

  test "#porter_admin_user_url :json => true" do
    url = @url_helper.porter_admin_user_url(
      user:    @user,
      options: { json: true },
    )

    assert_equal(
      "http://import2.test/admin/user/saw-the-light/#{@user.id}.json",
      url,
    )
  end
end
