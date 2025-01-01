# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerHttpTest < GitHub::IntegrationTestCase

  # Gists are not supported for EMU users, and is thus not supported at all in Proxima:
  # https://github.com/github/repos/issues/3061
  # If this ever changes, remove the skip_with_all_emus tag and fix the test.
  skip_with_all_emus

  include NewsiesHelper
  include UrlHelper
  include GistsHelper
  include UploadableTestHelpers
  include GistsControllerTestHelpers
  include HydroTestHelpers
  extend GistsControllerTestSetup

  setup do
    GitHub.flipper[:notifications_async_gist_subscription_button].disable
  end

  fixtures(&fixtures_block)
  setup(&global_setup_block)

  teardown do
    GitRepositoryBlock.expire_country_block_cache
  end

  context "new gist page" do
    test "it responds with a 200" do
      as @pub_user

      get "/gist"

      assert_response :success
      assert_select "input[type='radio'][name='gist[public]'][value='0'][checked='checked']"
      refute_select "input[type='radio'][name='gist[public]'][value='1'][checked='checked']"
    end

    test "it responds with a 200 and not available warning for EMUs", skip_enterprise: true do
      emu_user = create(:emu)

      as emu_user

      get "/gist"

      assert_response :success
      assert_includes response.body, "Gists for Enterprise Managed Users are disabled."
    end

    test "it preloads file contents from params" do
      as @pub_user

      get "/gist", params: { files: [{ name: "hello.rb", content: "puts 'hello'" }, { name: "empty.md" }] }

      assert_includes response.body, "hello.rb"
      assert_includes response.body, "puts &#39;hello&#39;"
      assert_includes response.body, "empty.md"
    end
  end

  context "create gist page" do
    test "it persists visibility choice" do
      as @pub_user

      params = {
        gist: {
          public: 1,
          contents: [{ name: "empty.md" }],
        },
      }
      post "/gist", params: params

      assert_response :success
      assert_includes response.body, "empty.md"
      refute_select "input[type='radio'][name='gist[public]'][value='0'][checked='checked']"
      assert_select "input[type='radio'][name='gist[public]'][value='1'][checked='checked']"
    end

    test "shows error when gist too large" do
      CommitsCollection.any_instance.stubs(:create).raises(GitRPC::RequestTooLarge.new(1))

      as @pub_user
      params = {
        gist: {
          contents: [{ name: "large_gist.md", value: "large contents" }],
        },
      }
      post "/gist", params: params

      assert_response :success
      assert_includes response.body, "large_gist.md"
      assert_select "div.flash.flash-full.flash-error [data-test-selector='flash-container']",
       text: "Contents are too large and cannot be saved"
    end
  end

  context "suggestions page" do
    context "logged in" do
      test "returns suggestions when given a valid and findable subject" do
        as @pub_user
        get gist_url_for(@pub_gist, path_segment: "suggestions"), xhr: true

        assert_response :ok
        assert_select "ul.emoji-suggestions"
      end

      test "returns user suggestions when given a user param" do
        as @pub_user
        get gist_url_for(@pub_gist, path_segment: "suggestions?target=user"), xhr: true

        assert_response :ok
        assert_equal JSON.parse(response.body).first["id"], @staff_user.id
      end
    end

    context "logged out" do
      test "fails" do
        get gist_url_for(@pub_gist, path_segment: "suggestions"), xhr: true
        if TestEnv.test_with_all_emus?
          assert_response_not_found
        else
          assert_response_unauthorized
        end
      end
    end
  end

  context "show page" do
    test "renders" do
      get gist_url_for(@pub_gist)

      assert_response_success
      assert_template "gists/gists/show"
      assert_includes response.body, @pub_gist_description
      assert_includes response.body, "id=\"file-hello-rb-L1\""
    end

    test "renders gists head page" do
      get gist_url_for(@pub_gist)

      assert_response_success
      assert_template "gists/gists/show"
      assert_includes response.body, "pagehead"
      assert_includes response.body, "pagehead-actions"
    end

    test "renders gists Subscribe button with async load enabled and custom error" do
      GitHub.flipper[:notifications_async_gist_subscription_button].enable

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_response :success
      assert_template "gists/gists/show"
      assert_select "[data-test-selector='subscription-button'] include-fragment[loading='lazy']", count: 1
      assert_includes response.body, "Couldn't load subscription status."
    end

    test "renders gists Subscribe button with async load enabled and the deferred content" do
      GitHub.flipper[:notifications_async_gist_subscription_button].enable

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_response :success
      assert_template "gists/gists/show"

      path = "/gist/#{@pub_user.display_login}/#{@pub_gist.repo_name}/subscription"
      assert_select "[data-test-selector='subscription-button'] include-fragment[loading='lazy'][src='#{path}']", count: 1
    end

    test "renders gists Subscribe button with async load enabled and deferred content with correct hidden custom error" do
      GitHub.flipper[:notifications_async_gist_subscription_button].enable

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_response :success
      assert_template "gists/gists/show"

      assert_select "[data-test-selector='subscription-button'] include-fragment[loading='lazy']", count: 1
      assert_includes response.body, "p data-show-on-error hidden", count: 1
      assert_includes response.body, "Couldn't load subscription status."
      refute_includes response.body, "Sorry, something went wrong and we weren't able to fetch your subscription status."
    end

    test "renders gists Subscribe button with async disabled" do
      GitHub.flipper[:notifications_async_gist_subscription_button].disable
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].disable

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_response :success
      assert_template "gists/gists/show"
      assert_select "[data-test-selector='subscription-button'] include-fragment[loading='lazy']", count: 0
    end

    test "redirects text format" do
      get "#{gist_url_for(@pub_gist)}.txt"
      assert_response :redirect
      if TestEnv.test_with_all_emus?
        assert_redirect_to_enterprise_sso
      else
        assert_redirected_to raw_user_gist_path(@pub_gist.user_param, @pub_gist)
      end
    end

    test "renders with unicode paths and file contents" do
      unicode_gist = GistHelpers.generate(
        user: @pub_user,
        description: "Unicode everywhere",
        contents: [
          { name: "こんにちは.rb", value: "puts 'こんにちは'" }
        ],
      )

      get gist_url_for(unicode_gist)

      assert_response_success
      assert_template "gists/gists/show"
    end

    test "renders with non-unicode paths and file contents" do
      weird_gist = GistHelpers.generate_with_example_repo(
        :gist_invalid_utf8_filenames,
        owner: @pub_user,
        description: "Non-unicode, eventually",
      )

      get gist_url_for(weird_gist)

      assert_response_success
      assert_template "gists/gists/show"
    end

    test "includes CSP headers for video uploads" do
      get gist_url_for(@pub_gist)

      assert_response_success

      refute_nil csp = SecureHeaders.header_hash_for(request)["Content-Security-Policy"]
      assert_match %r{media-src[^;]*#{GitHub.s3_user_asset_new_host}}, csp
    end

    test "renders video player for video uploads" do
      Timecop.freeze do
        video_asset = save_file_for_uploadable(UserAsset.new(uploader: @pub_user), name: "cool.mp4", content_type: "video/mp4")
        video_gist = GistHelpers.generate(
          user: @pub_user,
          description: "Video Player",
          contents: [
            { name: "test.md", value: "the video:\n\n#{video_asset.url}" }
          ],
        )
        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@pub_user, video_gist)
        end
        as @pub_user

        get gist_url_for(video_gist)

        assert_response_success
        assert_select "video[src=\"#{video_asset.url}\"]", count: 1
      end
    end

    test "renders 404 when gist is no longer available" do
      g = @pub_gist.delete
      get gist_url_for(g)
      assert_response :not_found
    end

    test "renders comments" do
      @pub_gist.comments.create(body: "1", user: create(:user, login: "commenter1"))
      @pub_gist.comments.create(body: "2", user: create(:user, login: "commenter2"))
      @pub_gist.comments.create(body: "3", user: create(:user, login: "commenter3"))

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end
      as @pub_user

      get gist_url_for(@pub_gist)

      assert_response_success
      #when authenticated, there will be a comment form (also .timeline-comment) along with the comments
      assert_select ".timeline-comment", count: 3
    end

    test "paginates comments when there are more than #{Gist::COMMENTS_PER_PAGE}" do
      total_comments = Gist::COMMENTS_PER_PAGE + 1
      total_comments.times do |i|
        @pub_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @pub_gist.reload

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE
      assert_select ".ajax-pagination-btn", count: 1
    end

    test "paginates comments when there are more than #{Gist::COMMENTS_PER_PAGE} for an anonymous gist" do
      total_comments = Gist::COMMENTS_PER_PAGE + 1
      total_comments.times do |i|
        @anonymous_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @anonymous_gist.reload

      get gist_url_for(@anonymous_gist) + "/load_comments"

      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE
      assert_select ".ajax-pagination-btn", count: 1
    end

    test "does not display load earlier comments button when there are fewer than #{Gist::COMMENTS_PER_PAGE}" do
      total_comments = Gist::COMMENTS_PER_PAGE - 1
      total_comments.times do |i|
        @pub_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @pub_gist.reload

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      get gist_url_for(@pub_gist)

      assert_select ".timeline-comment-group", count: total_comments
      assert_select ".ajax-pagination-btn", count: 0
    end

    test "displays permalinked comment and all later comments when there are more than #{Gist::COMMENTS_PER_PAGE}" do
      Gist::COMMENTS_PER_PAGE.times do |i|
        @pub_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @pub_gist.reload

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      permalink_comment_id = @pub_gist.comments[1].id
      get gist_url_for(@pub_gist) + "?permalink_comment_id=#{permalink_comment_id}#gistcomment-#{permalink_comment_id}"

      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE - 1
      assert_select ".ajax-pagination-btn", count: 1
    end

    test "displays permalinked comment and paginate later comments when there are more than #{Gist::COMMENTS_PER_PAGE}" do
      total_comments = (Gist::COMMENTS_PER_PAGE * 2)
      total_comments.times do |i|
        @pub_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @pub_gist.reload

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      permalink_comment_id = @pub_gist.comments[1].id
      get gist_url_for(@pub_gist) + "?permalink_comment_id=#{permalink_comment_id}#gistcomment-#{permalink_comment_id}"

      # 1 page of comments
      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE

      # Earlier and later pagination buttons
      assert_select ".ajax-pagination-btn", count: 2
      assert_select "form.ajax-pagination-form" do
        assert_select "button.ajax-pagination-btn", text: "Load earlier comments..."
      end
      assert_select "form.ajax-pagination-form.mb-5" do
        assert_select "button.ajax-pagination-btn.mt-0", text: "Load later comments..."
      end

      # Get another page
      after_comment_id = css_select("input[name=after_comment_id]").first["value"]
      get gist_url_for(@pub_gist) + "/load_comments?after_comment_id=#{after_comment_id}"

      # We've reached the end so don't need to render another next button
      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE - 1
      assert_select ".ajax-pagination-btn", count: 0
    end

    test "paginates comments when a user is logged out" do
      total_comments = Gist::COMMENTS_PER_PAGE + 1
      total_comments.times do |i|
        @pub_gist.comments.create(body: "#{i}", user: create(:user, login: "commenter#{i}"))
      end
      @pub_gist.reload

      get gist_url_for(@pub_gist)

      assert_response_success
      assert_select ".timeline-comment-group", count: Gist::COMMENTS_PER_PAGE
      assert_select ".ajax-pagination-btn", count: 1
    end

    test "shows comment edit history for deleted user" do
      deleted_user = create :user
      deleted_user_comment = create(:gist_comment, gist:  @pub_gist, body: "This is a gist comment body", user:  deleted_user)
      deleted_user_comment.update_body("New content", deleted_user_comment.user)
      deleted_user.destroy!

      as @pub_user
      get UrlHelpers.show_comment_edit_history_log_path(
            comment_id: deleted_user_comment.global_relay_id
          ), xhr: true

      assert_response :success
    end

    test "shows comment edit history on anonymous gist" do
      anonymous_gist = GitHub.override(:anonymous_gist_creation_enabled, true) do
        create :gist, public: false, user: nil
      end
      commentor = create :user
      commentor_comment = create(:gist_comment, gist:  anonymous_gist, body: "This is a gist comment body", user:  commentor)
      commentor_comment.update_body("New content", commentor_comment.user)

      as @pub_user
      get UrlHelpers.show_comment_edit_history_log_path(
            comment_id: commentor_comment.global_relay_id
          ), xhr: true

      assert_response :success
    end

    test "renders for anonymous gists" do
      @pub_gist.update_column :user_id, nil
      assert @pub_gist.anonymous?

      get gist_url_for(@pub_gist)

      assert_response :success
      assert_select "meta[content='noindex, nofollow, noarchive']"
    end

    test "limits the number of files rendered" do
      large_contents = 1.upto(350).map do |i|
        { name: "file-#{"%03d" % i}.txt", value: "contents #{i}" }
      end
      large_gist = GistHelpers.generate contents: large_contents

      get gist_url_for(large_gist)

      assert_includes response.body, "file-001.txt"
      assert_includes response.body, "file-300.txt"
      refute_includes response.body, "file-301.txt"
      refute_includes response.body, "file-350.txt"

      assert_includes response.body, "gist exceeds the recommended number of files", "expected a notice to be shown to the user"
    end

    test "never shows the suggested changes markdown button" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      get gist_url_for(@pub_gist)
      assert_select ".js-suggested-change-toolbar-item", false
    end

    test "includes open graph metadata" do
      request_env["HTTP_USER_AGENT"] = "Facebot/1.0"
      get gist_url_for(@pub_gist)

      assert_includes response.body, "og:url"
      assert_includes response.body, "og:site_name"
      assert_includes response.body, "og:title"
      assert_includes response.body, "og:description"
      assert_includes response.body, "og:image"
    end

    test "includes og_image as open graph image" do
      gist = GistHelpers.generate contents: [
          { name: "file1.txt", value: "contents1" },
          { name: "another_image.png", value: "PNG" },
          { name: "og_image.png", value: "PNG" },
        ]

      request_env["HTTP_USER_AGENT"] = "Facebot/1.0"
      get gist_url_for(gist)

      assert_match /\<meta property="og:image" content=".*\/gist\/anonymous\/.*\/og_image.png"/, response.body
    end

    test "includes default og_image as open graph image" do
      request_env["HTTP_USER_AGENT"] = "Facebot/1.0"
      get gist_url_for(@pub_gist)

      assert_includes response.body, "<meta property=\"og:image\" content=\"#{GitHub.asset_host_url}/images/modules/gists/gist-og-image.png\" />"
    end

    test "includes open graph metadata and descriptions in anonymous requests" do
      request_env["HTTP_USER_AGENT"] = "Facebot/1.0"
      @pub_gist.update_column :user_id, nil
      get gist_url_for(@pub_gist)

      assert_includes response.body, "og:url"
      assert_includes response.body, "og:site_name"
      assert_includes response.body, "og:title"
      assert_includes response.body, "og:image"

      descriptions = assert_select("meta[name='description']")
      assert_equal 1, descriptions.size

      description = descriptions.first
      assert_match(@pub_gist.description, description["content"])

      og_description = assert_select("meta[property='og:description']").first
      assert_match(@pub_gist.description, og_description["content"])
    end

    if GitHub.anonymized_private_repo_analytics?
      test "masks the location for google analytics" do
        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@pub_user, @pub_gist)
        end
        as @pub_user

        get gist_url_for(@pub_gist)

        assert_response_success
        assert_select "meta[name=\"analytics-location\"][content=\"/gist/<user-name>/<gist-id>\"]"
      end
    end

    test "renders JSON format" do
      get "#{gist_url_for(@pub_gist)}.json"

      assert_response_success
      assert_equal "application/json", response.media_type

      payload = {
        "description" => @pub_gist.description,
        "public" => @pub_gist.public,
        "created_at" => @pub_gist.created_at.as_json,
        "files" => @pub_gist.files.map(&:name),
        "owner" => @pub_gist.owner.login,
        "stylesheet" => gist_embed_stylesheet_url,
      }
      actual = JSON.parse(response.body)
      assert_includes actual.delete("div"), ERB::Util.force_escape(@pub_gist.files.first.data)
      assert_equal payload, actual
    end

    test "renders a JS embed when requested with JS format" do
      get gist_url_for(@pub_gist), format: "js"

      assert_response_success

      assert_equal "text/javascript", response.media_type
      assert_includes response.body, "document.write"
      assert_match %r{/gist\-embed(-\w+)?\.css}, response.body
      assert_includes response.body, "/#{@pub_gist.user_param}/#{@pub_gist.to_param}/raw/#{@pub_gist.sha}/hello.rb", "includes link to raw blob"
    end

    test "supports showing a specific file for JS embeds" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get gist_url_for(gist), params: { format: "js", file: "file2.txt" }

      assert_includes response.body, "contents2"
      refute_includes response.body, "contents1"
    end

    test "404s if specified file for JS embed is not found" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get gist_url_for(gist), params: { format: "js", file: "unknown.txt" }

      assert_response :not_found
      assert response.body.blank?
    end

    test "renders a embed content when requested with PIBB format" do
      get gist_url_for(@pub_gist), format: "pibb"

      assert_response_success
      assert_equal "text/html", response.media_type
      assert_includes response.body, "id=\"file-hello-rb-L1\""
      assert_match %r{/gist\-embed(-\w+)?\.css}, response.body
    end

    test "supports showing a specific file for PIBB embeds" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get gist_url_for(gist), params: { format: "pibb", file: "file2.txt" }

      assert_includes response.body, "contents2"
      refute_includes response.body, "contents1"
    end

    test "404s if specified file for PIBB embed is not found" do
      gist = GistHelpers.generate contents: [
        { name: "file1.txt", value: "contents1" },
        { name: "file2.txt", value: "contents2" },
      ]

      get gist_url_for(gist), params: { format: "pibb", file: "unknown.txt" }

      assert_response :not_found
      assert response.body.blank?
    end

    test "renders correctly when filenames have newlines" do
      gist = GistHelpers.generate contents: [{ name: "file\nbar.md", value: "contents1" }]

      get gist_url_for(gist)

      assert_response 200
      assert_includes response.body, "/#{gist.user_param}/#{gist.to_param}/raw/#{gist.sha}/file%250Abar.md", "includes link to raw blob"
    end

    test "marks the gist as read async", skip_enterprise: true do
      user = create(:user)
      enable_notifications_for_user(user, enabled_handlers: ["web"])

      gist_content = [{ name: "bar.md", value: "contents1" }]
      gist = GistHelpers.generate(contents: gist_content, user: user, created_at: 10.days.ago)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        gist.comments.create(body: "Hi", user: create(:user))
      end

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(user, gist)
      end

      as user
      get gist_url_for(gist)

      assert_hydro_published({ user_id: user.id, threads: [gist.to_global_id.to_s] }, schema: "notifications.v0.MarkAsRead")
    end

    test "includes Spamurai form signals in the new comment form" do
      GitHub.stubs(:spamminess_check_enabled?).returns(true)

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      get gist_url_for(@pub_gist)

      # Make sure we rendered successfully.
      assert_response :success
      assert_template "gists/gists/show"

      # Make sure a Spamurai field was part of the new comment form.
      assert_select ".gist-content .js-new-comment-form input[name='timestamp_secret']"
    end

    unless GitHub.enterprise?
      test "renders spammy gist for staff", spammy_only: true do
        user = create(:user)
        gist = GistHelpers.generate(user: user, contents: @create_contents)

        reason = "Gist is spammy because X"
        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { user.mark_as_spammy(reason: reason, actor: @staff_user) }

        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@staff_user, gist)
        end

        as @staff_user
        get gist_url_for(gist)

        assert_response_success
        assert_includes response.body, "owner of this gist is flagged"
      end
    end

    # DMCA and Country blocking access control
    unless GitHub.enterprise?
      test "cannot show gist disabled for dmca" do
        @pub_gist.access.disable("dmca", @pub_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        as @pub_user

        get gist_url_for(@pub_gist)

        assert_response :success
        assert_template "gists/gists/states/dmca"
      end

      test "can show a gist with country block and no country in request" do
        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@pub_user, @pub_gist)
        end

        as @pub_user

        @pub_gist.access.country_block(
          @pub_user,
          GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
          "https://github.com/github/nation-state-blocks/blob/master/2011/2011-01-27-sony.markdown",
          "Reason for country block")
        get gist_url_for(@pub_gist)
        assert_response 200
        assert_template "gists/gists/show"
      end

      test "can show a gist with country block and different country in request" do
        request_env["HTTP_X_COUNTRY"] = "NL"

        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@pub_user, @pub_gist)
        end

        as @pub_user

        @pub_gist.access.country_block(
          @pub_user,
          GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
          "https://github.com/github/nation-state-blocks/blob/master/2011/2011-01-27-sony.markdown",
          "Reason for country block")
        get gist_url_for(@pub_gist)

        assert_response 200
        assert_template "gists/gists/show"
      end

      test "cannot show a gist with country block for blocked country" do
        request_env["HTTP_X_COUNTRY"] = "RU"
        as @pub_user

        @pub_gist.access.country_block(
          @pub_user,
          GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
          "https://github.com/github/nation-state-blocks/blob/master/2011/2011-01-27-sony.markdown",
          "Reason for country block")
        get gist_url_for(@pub_gist)

        assert_response 200
        assert_template "gists/gists/states/nation_blocklist"
      end
    end

    test "cannot show a private gist to ofac sanctioned users" do
      as @ofac_user

      get gist_url_for(@secret_gist)

      assert_response 200
      assert_template "gists/gists/states/ofac"
    end

    test "does not block public gists to ofac sanctioned users" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@ofac_user, @pub_gist)
      end

      as @ofac_user

      get gist_url_for(@pub_gist)

      assert_response 200
      assert_template "gists/gists/show"
    end

    test "renders when given a specific revision" do
      rev1 = @pub_gist.sha

      # Update pub_gist
      contents = @update_contents.dup
      contents.first[:value] = "NEW Content!!!"
      @pub_gist.contents = contents
      @pub_gist.save!

      # Double check that changes were committed
      rev2 = @pub_gist.reload.sha
      refute_equal rev1, rev2
      assert_includes @pub_gist.files.first.data, "NEW Content!!!"
      refute_includes @pub_gist.files.first.data, "hello"

      get gist_url_for(@pub_gist, path_segment: rev1)

      # Assert we're looking at the old revision
      assert_response_success
      assert_template "gists/gists/show"
      assert_includes response.body, "hello"
    end

    test "404s when a specific revision is not found" do
      get gist_url_for(@pub_gist, path_segment: "foo.json")
      assert_response_not_found
    end

    test "doesn't sanitize referrers for public gists" do
      get gist_url_for(@pub_gist)

      assert_response_success
      bad_tags = css_select("meta").find_all do |tag|
        tag["name"] == "referrer" && tag["content"] == "origin"
      end
      assert_predicate bad_tags, :empty?
    end

    test "don't sanitize referrers for secret gists in some browsers" do
      # Previously, Safari, IE, and Edge didn't support the Referrer-Policy header, so we
      # set a meta tag referrer policy here.
      # Now, that they fully support it we should let security_headers.rb handle it.
      # See security_headers_test.rb for tests that test Referrer-Policy explicitly.
      # The Referrer-Policy header can't be tested here, as it is set in middleware,
      # which isn't enabled in controller tests.
      request_env["HTTP_USER_AGENT"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"
      get gist_url_for(@secret_gist)
      assert_response_success
      refute_match %r{meta.*?content.*?origin}, response.body
    end

    test "includes noindex tag for secret gists" do
      get gist_url_for(@secret_gist)

      assert_response_success
      assert_select "meta[name=robots]" do
        assert_select "[content=?]", "noindex, follow"
      end
    end

    test "404s when requested with the keys format" do
      get "#{gist_url_for(@pub_gist)}.keys"
      assert_response_not_found
    end

    test "404s when requested with the unknown format" do
      get "#{gist_url_for(@pub_gist)}.php"
      assert_response_not_found
    end


    test "returns a 404 for an invalid gist" do
      get "/gist/some/non-sense"
      assert_response_not_found
    end

    test "failbot context contains gist repo name" do
      Gists::GistsController.any_instance.stubs(:commit_sha).raises(StandardError)
      assert_raises(StandardError) { get gist_url_for(@pub_gist) }

      report = Failbot.reports.last
      assert_equal report["gh.gist.repo_name"], @pub_gist.repo_name
    end
  end

  context "subscription" do
    test "renders the subscription button" do
      user = create(:verified_user)

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(user, @pub_gist)
      end

      refute @pub_gist.subscribed?(user)

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(user, @pub_gist)
      end


      as user
      get gist_url_for(@pub_gist, path_segment: "subscription")

      assert_select "button", text: "Subscribe"
    end
  end

  context "subscribe", feature_disabled: :notifyd_enable_gist_thread_subscriptions do
    test "subscribes the user to the gist" do
      user = create(:verified_user)
      refute @pub_gist.subscribed?(user)

      as user
      post gist_url_for(@pub_gist, path_segment: "subscribe"), params: { id: "subscribe" }

      assert @pub_gist.subscribed?(user)
    end

    test "unsubscribes the user from the thread" do
      user = create(:verified_user)

      @pub_gist.subscribe(user, :manual)
      assert @pub_gist.subscribed?(user)

      as user
      post gist_url_for(@pub_gist, path_segment: "subscribe"), params: { id: "unsubscribe" }

      refute @pub_gist.subscribed?(user)
    end

    test "mutes the thread" do
      user = create(:verified_user)

      @pub_gist.subscribe(user, :manual)
      assert @pub_gist.subscribed?(user)

      as user
      post gist_url_for(@pub_gist, path_segment: "subscribe"), params: { id: "mute" }

      refute @pub_gist.subscribed?(user)
    end

    test "redirects to the gist if not via xhr" do
      user = create(:verified_user)

      refute @pub_gist.subscribed?(user)

      as user
      post gist_url_for(@pub_gist, path_segment: "subscribe"), params: { id: "subscribe" }

      assert_redirected_to user_gist_path(@pub_gist.user_param, @pub_gist)
    end

    test "renders the subscription button if via xhr" do
      user = create(:verified_user)

      refute @pub_gist.subscribed?(user)

      as user
      post gist_url_for(@pub_gist, path_segment: "subscribe"), params: { id: "subscribe" }, xhr: true

      assert_response :ok
    end

    test "returns a 404 for an invalid gist" do
      as @pub_user
      post "/gist/some/non-sense", params: { id: "subscribe" }

      assert_response :not_found
    end
  end

  context "gist stargazers page" do
    test "renders" do
      spammy_user = create(:user, spammy: true)
      spammy_user.star @pub_gist
      @priv_user.star @pub_gist

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user

      get gist_url_for(@pub_gist, path_segment: "stargazers")

      assert_response :success
      assert_template "gists/gists/stargazers"
      assert_includes response.body, @priv_user.login
      refute_includes response.body, spammy_user.login unless GitHub.enterprise? || TestEnv.test_with_all_emus?

      etag = ActiveSupport::Digest.hexdigest(ActiveSupport::Cache.expand_cache_key(@pub_gist.viewer_cache_key(@pub_user)))
      assert_equal %("#{etag}"), @response.headers["ETag"]

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@staff_user, @pub_gist)
      end

      # Should render the Spammy user for staff
      as @staff_user

      get gist_url_for(@pub_gist, path_segment: "stargazers")

      assert_response :success
      assert_template "gists/gists/stargazers"
      assert_includes response.body, @priv_user.login
      assert_includes response.body, spammy_user.login

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(spammy_user, @pub_gist)
      end

      # Spammy user should see themself in the list
      as spammy_user

      get gist_url_for(@pub_gist, path_segment: "stargazers")

      assert_response :success
      assert_template "gists/gists/stargazers"
      assert_includes response.body, @priv_user.login
      assert_includes response.body, spammy_user.login
    end

    unless GitHub.enterprise?
      test "cannot show gist disabled for dmca" do
        @pub_gist.access.disable("dmca", @pub_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        as @pub_user

        get gist_url_for(@pub_gist, path_segment: "stargazers")

        assert_response :success
        assert_template "gists/gists/states/dmca"
      end
    end
  end

  context "gist forks page" do
    test "renders" do
      @pub_gist.fork @priv_user

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user

      get gist_url_for(@pub_gist, path_segment: "forks")

      assert_response_success
      assert_template "gists/gists/forks"
      assert_includes response.body, @priv_user.login

      etag = ActiveSupport::Digest.hexdigest(ActiveSupport::Cache.expand_cache_key(@pub_gist.viewer_cache_key(@pub_user)))
      assert_equal %("#{etag}"), @response.headers["ETag"]
    end

    unless GitHub.enterprise?
      test "cannot show gist disabled for dmca" do
        @pub_gist.access.disable("dmca", @pub_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        as @pub_user

        get gist_url_for(@pub_gist, path_segment: "forks")

        assert_response :success
        assert_template "gists/gists/states/dmca"
      end
    end
  end
end
