# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadReleasePayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple

    # Contains tags 'v1' and 'v2'

    @release = create :release, repository: @repo, author: @user, tag_name: "v1"

    if GitHub.multi_tenant_enterprise?
      @enterprise_org = create(:organization, :enterprise_managed_organization)
      @enterprise_repo = create(:repository, owner: @enterprise_org, from_example: :repository_test_simple)
      @enterprise_user = @enterprise_org.admin
    end
  end

  test "v3 structure for published action" do
    event   = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :published, actor_id: @user.id
    payload = Hook::Payload::ReleasePayload.new event

    v3 = payload.to_hash

    assert_equal :published, v3[:action]
    assert_equal @release.id, v3[:release][:id]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.display_login, v3[:sender][:login]
  end

  test "v3 structure for edited action" do
    changes = { old_body: "v1", make_latest: true }
    event   = Hook::Event::ReleaseEvent.new release_id: @release.id, action: :edited, actor_id: @user.id, changes: changes
    payload = Hook::Payload::ReleasePayload.new event

    v3 = payload.to_hash

    assert_equal :edited, v3[:action]
    assert_equal @release.id, v3[:release][:id]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.display_login, v3[:sender][:login]
    assert_equal "v1", v3[:changes][:body][:from]
    assert_equal true, v3[:changes][:make_latest][:to]
  end

  test "uses display_login in URL fields" do
    refute_equal @enterprise_org.login, @enterprise_org.display_login,
      "need an org whose login differs from its display_login"
    refute_equal @enterprise_repo.owner_login, @enterprise_repo.owner_display_login,
      "need a repo whose owner_login differs from its owner_display_login"
    refute_equal @enterprise_user.login, @enterprise_user.display_login,
      "need a user whose login differs from their display_login"
    release = create(:release, repository: @enterprise_repo, author: @enterprise_user, tag_name: "v1")
    event = Hook::Event::ReleaseEvent.new(release_id: release.id, action: :published, actor_id: @enterprise_user.id)
    payload = Hook::Payload::ReleasePayload.new(event)

    v3 = payload.to_hash

    assert_equal "#{GitHub.url}/#{@enterprise_user.display_login}", v3[:sender][:html_url]
    assert_equal "#{GitHub.url}/#{@enterprise_org.display_login}", v3[:repository][:owner][:html_url]
    user_url_fields = %i[url followers_url following_url gists_url starred_url subscriptions_url organizations_url
      repos_url events_url received_events_url]
    user_url_fields.each do |field|
      assert_includes v3[:sender][field], "/users/#{@enterprise_user.display_login}",
        "expected sender #{field} field to use display_login"
      assert_includes v3[:repository][:owner][field], "/users/#{@enterprise_org.display_login}",
        "expected repo owner #{field} field to use display_login"
    end
    assert_equal "#{GitHub.url}/#{@enterprise_repo.name_with_display_owner}", v3[:repository][:html_url]
    repo_url_fields = %i[url forks_url keys_url collaborators_url teams_url hooks_url issue_events_url events_url
      assignees_url branches_url tags_url blobs_url git_tags_url git_refs_url trees_url statuses_url languages_url
      stargazers_url contributors_url subscribers_url subscription_url commits_url git_commits_url comments_url
      issue_comment_url contents_url compare_url merges_url archive_url downloads_url issues_url pulls_url
      milestones_url notifications_url labels_url releases_url deployments_url git_url clone_url svn_url]
    repo_url_fields.each do |field|
      assert_includes v3[:repository][field], "/#{@enterprise_repo.name_with_display_owner}",
        "expected repo #{field} field to use repo name_with_display_owner"
    end
  end if GitHub.multi_tenant_enterprise?

  test "uses display_login in tarball_url and zipball_url fields" do
    published_release = create(:release, :published, repository: @enterprise_repo, author: @enterprise_user,
      tag_name: "v1.5")
    event = Hook::Event::ReleaseEvent.new(release_id: published_release.id, action: :edited,
      actor_id: @enterprise_user.id)
    payload = Hook::Payload::ReleasePayload.new(event)

    v3 = payload.to_hash

    assert_includes v3[:release][:tarball_url], "/#{@enterprise_org.display_login}/#{@enterprise_repo.name}"
    assert_includes v3[:release][:zipball_url], "/#{@enterprise_org.display_login}/#{@enterprise_repo.name}"
  end if GitHub.multi_tenant_enterprise?
end
