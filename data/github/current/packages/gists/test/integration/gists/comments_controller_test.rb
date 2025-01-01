# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsCommentsControllerHttpTest < GitHub::IntegrationTestCase
  # Managed user accounts cannot create gists or comment on gists.
  # https://docs.github.com/enterprise-cloud@latest/admin/identity-and-access-management/using-enterprise-managed-users-for-iam/about-enterprise-managed-users#abilities-and-restrictions-of-managed-user-accounts
  skip_with_all_emus

  include GistsControllerTestHelpers

  mention_limit = GitHub::HTML::MentionFilter::MENTION_LIMIT

  fixtures do
    create_contents = [{ name: "hello.rb", value: "def hello; puts 'Hello!'; end" }]

    @staff = create :staff_admin_user, login: "staffy"
    # Managed user accounts cannot create gists or comment on gists
    @gist_author = create(:user, login: "gistuser", plan: "large", skip_enterprise_managed_user: true)
    @gist = GistHelpers.generate(user: @gist_author, contents: create_contents)
    @gist_comment = @gist.comments.create(body: "blah blah!", user: create(:user, login: "commenter1", skip_enterprise_managed_user: true))

    @spammer = create :user, spammy: true
    @spammy_comment = @gist.comments.create(body: "blog spam", user: @spammer)

    @users = (0..(mention_limit + 5)).map { |i| create :user, login: "user#{i}" }

    @ghost_user = create :user, login: "spooky"
    @ghost_comment = @gist.comments.create(body: "blah blah!", user: @ghost_user)

    GitHub.flipper[:notifications_async_gist_subscription_button].disable
  end

  test "can add a comment to an gist" do
    as @gist.user
    post "/gist/#{@gist.name_with_display_owner}/comments", params: { comment: { body: "Fresh Comment" } }
    comment = GistComment.last
    assert_equal "Fresh Comment", T.must(comment).body

    assert_response :redirect
    assert_redirected_to "/gist/#{@gist.name_with_display_owner}#gistcomment-#{T.must(comment).id}"
  end

  test "commenting on an gist via ajax" do
    as @gist.user

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "Fresh Comment" } }, xhr: true
    assert_response :success

    comment = GistComment.last
    assert_equal "Fresh Comment", T.must(comment).body
  end

  test "commenting on an gist via ajax triggers a Google analytics event" do
    as @gist.user

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "Fresh Comment" } }, xhr: true

    assert_response :success
    assert_includes @response.body, %q{data-ga-load=\"Gist, Comment, public owned\"}
  end

  test "blocked users should not be able to comment on gists" do
    blocked_user = create(:user)
    @gist_author.block(blocked_user)
    as blocked_user
    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "Fresh Comment" } }, xhr: true
    assert_response :unprocessable_entity
    data = GitHub::JSON.decode(@response.body)
    assert_equal ["cannot be saved"], data["errors"]
  end

  test "validation failures for new comments via ajax" do
    as @gist.user

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "" } }, xhr: true
    assert_response :unprocessable_entity
    data = GitHub::JSON.decode(@response.body)
    assert_equal ["can't be blank"], data["errors"]
  end

  test "commenting on an stale issue via ajax" do
    as @gist.user

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "Fresh Comment" } }, xhr: true
    assert_response :success

    request_env["X_TIMELINE_LAST_MODIFIED"] = (T.must(T.must(GistComment.last).created_at) - 1.second).httpdate
    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "Stale Comment" } }, xhr: true
    assert_response :success
  end

  test "cannot create a blank comment" do
    request_env["HTTP_REFERER"] = "/gist/#{@gist.owner}"
    as @gist.user

    count = GistComment.count

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { comment: { body: "" } }

    assert_equal count, GistComment.count

    assert_response :redirect
    assert_redirected_to "/gist/#{@gist.owner}"
  end

  test "cannot create a blank comment via ajax" do
    as @gist.user

    count = GistComment.count

    post "/gist/#{@gist.name_with_display_owner}/comments", params: { format: "json", comment: { body: "" } }, xhr: true

    assert_response :unprocessable_entity
    assert_equal count, GistComment.count
  end

  test "adds Spamurai form signals to request context when creating a comment" do
    mock_form_signals = { mock_signal: true }
    ApplicationController.any_instance.expects(:spamurai_form_signals).returns(mock_form_signals)

    refute_includes GitHub.context.to_hash, :spamurai_form_signals

    as @gist.user
    post(
      "/gist/#{@gist.name_with_display_owner}/comments",
      params: { format: "json", comment: { body: "Fresh Comment" } },
      xhr: true,
    )

    assert_response :success
    assert_equal GitHub.context[:spamurai_form_signals], mock_form_signals
  end

  if GitHub.prevent_mention_spam?
    test "is still created even when user mentions are limited", spammy_only: true do
      body = @users[0, mention_limit + 1].map { |u| "@#{u}" }.join(", ")

      as @gist.user
      post "/gist/#{@gist.name_with_display_owner}/comments", params: { comment: { body: body } }
      comment = GistComment.last

      assert_response :redirect
      assert_redirected_to "/gist/#{@gist.name_with_display_owner}#gistcomment-#{T.must(comment).id}"
      assert_equal mention_limit, T.must(comment).mentioned_users.length
    end
  else
    test "is unaffected by user-mention limits" do
      body = @users[0, mention_limit + 1].map { |u| "@#{u}" }.join(", ")

      as @gist.user
      post "/gist/#{@gist.name_with_display_owner}/comments", params: { comment: { body: body } }
      comment = GistComment.last

      assert_response :redirect
      assert_redirected_to "/gist/#{@gist.name_with_display_owner}#gistcomment-#{T.must(comment).id}"
      assert_equal mention_limit + 1, T.must(comment).mentioned_users.length
    end
  end

  test "can be edited by the gist owner" do
    as @gist.user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Hooray!" } }
    @gist_comment.reload
    assert_includes @gist_comment.body, "Hooray!"
  end

  test "can be edited by the comment author" do
    refute_equal @gist.user, @gist_comment.user

    as @gist_comment.user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Hooray!" } }
    @gist_comment.reload
    assert_includes @gist_comment.body, "Hooray!"
  end

  test "can be edited by GitHub staff" do
    as @staff
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Staff Edits are the stealthiest edits" } }
    @gist_comment.reload
    assert_includes @gist_comment.body, "Staff Edits are the stealthiest edits"
  end

  test "blocked users should not be able to edit their gist comments" do
    blocked_user = @gist_comment.user
    @gist_author.block(blocked_user)
    as blocked_user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { format: "json", gist_comment: { body: "Something inflammatory!!!" } }
    assert_response :unprocessable_entity
    data = GitHub::JSON.decode(@response.body)
    assert_equal ["Message cannot be saved"], data["errors"]
  end

  test "uses the editing user (not the original user) permissions" do
    reset_cache
    enable_cache_storage(/body_html:/)

    owner = @gist.user
    user = @gist_comment.user

    owner.update(plan: "medium")
    user.update(plan: "medium")

    user_private_repo   = create(:private_repository, owner: user)
    owner_private_repo  = create(:private_repository, owner: owner)
    user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
    owner_private_issue = create(:issue, repository: owner_private_repo, user: owner)

    user_private_reference  = [user_private_repo.name_with_owner,  user_private_issue.number].join("#")
    owner_private_reference = [owner_private_repo.name_with_owner, owner_private_issue.number].join("#")

    as owner

    new_body  = "Hooray! Editing the issue with some references: "
    new_body += owner_private_reference + " "
    new_body += user_private_reference

    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: new_body } }

    @gist_comment.reload

    assert_includes @gist_comment.body, "Hooray!"
    assert_includes @gist_comment.body_html, %Q[href="#{owner_private_issue.permalink}"]
    refute_includes @gist_comment.body_html, %Q[href="#{user_private_issue.permalink}"]
  end

  test "uses the editing user (not the original user) permissions for xhr" do
    reset_cache
    enable_cache_storage(/body_html:/)

    owner = @gist.user
    user = @gist_comment.user

    owner.update(plan: "medium")
    user.update(plan: "medium")

    user_private_repo   = create(:private_repository, owner: user)
    owner_private_repo  = create(:private_repository, owner: owner)
    user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
    owner_private_issue = create(:issue, repository: owner_private_repo, user: owner)

    user_private_reference  = [user_private_repo.name_with_owner,  user_private_issue.number].join("#")
    owner_private_reference = [owner_private_repo.name_with_owner, owner_private_issue.number].join("#")

    as owner

    new_body  = "Hooray! Editing the issue with some references: "
    new_body += owner_private_reference + " "
    new_body += user_private_reference

    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { format: "json", gist_comment: { body: new_body } }, xhr: true

    @gist_comment.reload

    assert_includes @gist_comment.body, "Hooray!"
    assert_includes @gist_comment.body_html, %Q[href="#{owner_private_issue.permalink}"]
    refute_includes @gist_comment.body_html, %Q[href="#{user_private_issue.permalink}"]
  end

  test "can't be edited by randoms" do
    as @maddox
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Hooray!" } }
    @gist_comment.reload
    assert_includes @gist_comment.body, "blah blah!"
  end

  test "can be edited via json" do
    as @gist.user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Hooray!" }, format: "json" }, xhr: true
    assert_response :success
    @gist_comment.reload
    assert_includes @gist_comment.body, "Hooray!"
  end

  test "body can't be blank" do
    old_body = @gist_comment.body
    as @gist.user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "" }, format: "json" }, xhr: true
    assert_response :unprocessable_entity
    @gist_comment.reload
    assert_equal old_body, @gist_comment.body
  end

  test "gracefully handles malformed params" do
    old_body = @gist_comment.body
    as @gist.user
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { blah_comment: "3", format: "json" }, xhr: true
    assert_response :unprocessable_entity
    @gist_comment.reload
    assert_equal old_body, @gist_comment.body
  end

  test "can be deleted by gist owner" do
    as @gist.user
    delete "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
    refute GistComment.exists?(@gist_comment.id)
  end

  test "can be deleted by comment author" do
    as @gist_comment.user
    delete "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
    refute GistComment.exists?(@gist_comment.id), "GistComment #{@gist_comment.id} exists when it shouldn't."
  end

  test "can be deleted by GitHub staff" do
    as @staff
    delete "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
    refute GistComment.exists?(@gist_comment.id)
  end

  test "can't be deleted by randoms" do
    as @maddox
    delete "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
    assert GistComment.exists?(@gist_comment.id)
  end

  test "can't be edited by anonymous" do
    put "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}", params: { gist_comment: { body: "Hooray!" } }
    @gist_comment.reload
    assert_includes @gist_comment.body, "blah blah!"
  end

  test "can't be deleted by anonymous" do
    delete "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
    assert GistComment.exists?(@gist_comment.id)
  end

  context "Viewing a commit comment" do
    test "renders comment when it exists" do
      get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
      assert_response_success
      assert_includes response.body, @gist_comment.body
    end

    test "renders a 404 when there is no comment" do
      @gist_comment.destroy
      get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}"
      assert_response_not_found
    end
  end

  context "when spamminess is enabled", spammy_only: true do
    test "spammy comments are visible to the spammer" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@spammer, @gist)
      end

      as @spammer
      get "/gist/#{@gist.name_with_display_owner}"

      assert_includes response.body, "blog spam"
    end

    test "spammy comments are visible to staff" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@staff, @gist)
      end

      as @staff
      get "/gist/#{@gist.name_with_display_owner}"

      assert_includes response.body, "blog spam"
    end

    test "spammy comments are NOT visible to the gist author" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@gist_author, @gist)
      end

      as @gist_author
      get "/gist/#{@gist.name_with_display_owner}"

      refute_includes response.body, "blog spam"
    end

    test "spammy comments are NOT visible to regular users" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@users.first, @gist)
      end

      as @users.first
      get "/gist/#{@gist.name_with_display_owner}"

      refute_includes response.body, "blog spam"
    end

    context "for the gist author" do
      test "the comment_actions_menu shows the correct items for a comment by another user" do
        as @gist_author
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}/comment_actions_menu", xhr: true

        assert_response :success

        assert_includes response.body, "Copy link"
        assert_includes response.body, "Quote reply"
        assert_includes response.body, "Edit"
        assert_includes response.body, "Delete"
        assert_includes response.body, "Report"
      end

      test "the comment_actions_menu show the correct items for a comment by a ghost commentor" do
        @ghost_user.destroy
        @ghost_comment.reload
        assert_nil @ghost_comment.user

        as @gist_author
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@ghost_comment.id}/comment_actions_menu", xhr: true

        assert_response :success

        assert_includes response.body, "Copy link"
        assert_includes response.body, "Quote reply"
        refute_includes response.body, "Edit"
        assert_includes response.body, "Delete"
        assert_includes response.body, "Report"
      end
    end

    context "for regular users" do
      test "the comment_actions_menu shows the correct items for a comment by another user" do
        as @users.first
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}/comment_actions_menu", xhr: true

        assert_response :success

        assert_includes response.body, "Copy link"
        assert_includes response.body, "/gist/#{@gist.name_with_display_owner}?permalink_comment_id=#{@gist_comment.id}#gistcomment-#{@gist_comment.id}"
        assert_includes response.body, "Quote reply"
        assert_includes response.body, "Report"
        refute_includes response.body, "Edit"
        refute_includes response.body, "Delete"
      end

      test "the comment_actions_menu show the correct items for a comment by a ghost commentor" do
        @ghost_user.destroy
        @ghost_comment.reload
        assert_nil @ghost_comment.user

        as @users.first
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@ghost_comment.id}/comment_actions_menu", xhr: true

        assert_response :success

        assert_includes response.body, "Copy link"
        assert_includes response.body, "Quote reply"
        refute_includes response.body, "Edit"
        refute_includes response.body, "Delete"
        assert_includes response.body, "Report"
      end

      test "the comment edit_form responds 403 for" do
        as @users.first
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}/edit_form", xhr: true

        assert_response :forbidden
      end

      test "the comment edit_form responds 404 for a non-existent gist" do
        as @users.first
        get "/gist/#{@gist_author.login}/123456/comments/123456/edit_form", xhr: true

        assert_response :not_found
      end
    end

    context "for the comment author" do
      test "the comment edit_form responds with the edit form for the comment author" do
        as @gist_comment.user
        get "/gist/#{@gist.name_with_display_owner}/comments/#{@gist_comment.id}/edit_form", xhr: true

        assert_response :success
        assert_includes response.body, "Update comment"
      end
    end
  end
end
