# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsUsersControllerHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  # Controller returns 404 for EMUs
  skip_with_all_emus

  fixtures &fixtures_block

  setup &global_setup_block

  context "legacy redirects" do
    test "redirects top level :gist_id requests" do
      get "/gist/#{@pub_gist.repo_name}"

      assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}"
      assert_response 302
    end

    test "keeps notifications parameters during top level :gist_id redirect" do
      notifications_params = "notification_referrer_id=1&notifications_after=1&notifications_before=3&notifications_query=aquery"
      get "/gist/#{@pub_gist.repo_name}?#{notifications_params}"

      assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}?#{notifications_params}"
      assert_response 302
    end

    test "redirects top level :gist_id/stars" do
      get "/gist/#{@pub_gist.repo_name}/stars"

      assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}/stargazers"
      assert_response 302
    end

    test "redirects top level :gist_id/forks" do
      get "/gist/#{@pub_gist.repo_name}/forks"

      assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}/forks"
      assert_response 302
    end

    test "redirects top level :gist_id/revisions" do
      get "/gist/#{@pub_gist.repo_name}/revisions"

      assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}/revisions"
      assert_response 302
    end
  end

  context "colliding namespace" do
    test "prefers Gists for Gist formats" do
      gist_extensions = [".js", ".json", ".pibb", ".txt", ".git"]
      user = create(:user, login: @pub_gist.repo_name)

      Gist::FORMATS.each do |extension|
        get "/gist/#{@pub_gist.repo_name}#{extension}"
        assert_redirected_to "/gist/#{@pub_gist.user_param}/#{@pub_gist.repo_name}#{extension}", "#{extension} should have redirected"
        assert_response 302
      end
    end

    test "prefers Users for User formats" do
      user_extensions = [".atom", ""]
      user = create(:user, login: @pub_gist.repo_name)

      user_extensions.each do |extension|
        get "/gist/#{user.login}#{extension}"
        assert_response 200
      end
    end
  end

  context "user profile" do
    context "viewing your page" do
      test "shows banner for conflicting gist repo_name" do
        as @pub_user

        namespace = Gist.generate_unique_repo_name
        user = create(:user, login: namespace)

        get "/gist/#{user.display_login}"
        assert_response :success
        refute_includes response.body, "Looking for a Gist?"

        gist = create(:gist, repo_name: namespace)

        get "/gist/#{user.display_login}"
        assert_response :success
        assert_includes response.body, "Looking for a Gist?"
        assert_includes response.body, "View #{gist.owner.login}/#{gist.repo_name}"
      end

      test "doesn't raise when conflicting namespace with anonymous gist" do
        as @pub_user

        user = create(:user, login: @anonymous_gist.repo_name)

        get "/gist/#{user.display_login}/1d331f99aedd42201ce2494c14c28384402f909d"
        assert_response :success
        assert_includes response.body, "Looking for a Gist?"
        assert_includes response.body, "View anonymous/#{@anonymous_gist.repo_name}"
      end

      test "atom requests are rendered" do
        as @pub_user
        get "/gist/#{@pub_user.display_login}.atom"

        assert_response :success
        assert_template "gists/listings/feed"
        assert_equal "application/atom+xml", response.media_type
        assert_includes response.body, @pub_gist_description
      end

      test "404's with an invalid user id" do
        as @pub_user
        get "/gist/made-up-shenanigans"

        assert_response :not_found
      end

      test "handles timeout errors" do
        Gist.any_instance.stubs(:title).raises(ApplicationHelper::GitTemplateTimeout)

        get "/gist/#{@pub_user.display_login}"

        assert_response :success
        assert_includes response.body, "Timeout rendering snippet for #{@pub_user.display_login}"
      end

      # https://github.com/github/github/issues/107459
      test "does not error when visiting an organization's profile" do
        member = create(:user)
        @org.add_member(member)
        GistHelpers.generate(user: member, description: "Sample gist",
                      contents: [{ name: "newfile.md", value: "### HEADER" }])

        get "/gist/#{@org.display_login}"

        assert_response :ok
      end
    end

    context "viewing someone else's page" do
      # https://github.com/github/github/issues/101577
      test "does not error when CSV parsing results in an empty array" do
        GistHelpers.generate(user: @pub_user, contents: [
          { name: "output.csv", value: "cat,dog" },
        ])
        CSV.stubs(:parse).returns([])

        get "/gist/#{@pub_user.display_login}"

        assert_response :ok
      end

      test "does not include DMCA'd gists", skip_enterprise: true do
        @pub_gist.access.disable("dmca", @staff_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        get "/gist/#{@pub_user.display_login}"

        assert_response :ok
        assert_select "a[href='/gist/#{@pub_gist.name_with_display_owner}']", count: 0
      end

      test "doesn't show private gists to anon users" do
        GistHelpers.generate(user: @priv_user,
          contents: @create_contents, public: false)

        assert_equal 0, @priv_user.gists.are_public.count
        assert @priv_user.gists.are_secret.count > 0

        get "/gist/#{@priv_user.display_login}"
        assert_response :success
        refute_includes response.body, "id=\"file-hello-rb-L1\""
        assert_includes response.body, "doesn’t have any public gists yet"
      end

      test "atom requests are rendered to anon users" do
        GistHelpers.generate(user: @priv_user,
          contents: @create_contents, description: "private secrets",
          public: false)

        get "/gist/#{@priv_user.display_login}.atom"

        assert_response :success
        assert_template "gists/listings/feed"
        assert_equal "application/atom+xml", response.media_type
        refute_includes response.body, "private secrets"
      end

      test "doesn't show private gists to auth'd users" do
        GistHelpers.generate(user: @priv_user,
          contents: @create_contents, public: false)

        assert_equal 0, @priv_user.gists.are_public.count
        assert @priv_user.gists.are_secret.count > 0

        as @pub_user
        get "/gist/#{@priv_user.display_login}"
        assert_response :success
        refute_includes response.body, "id=\"file-hello-rb-L1\""
        assert_includes response.body, "doesn’t have any public gists yet"
      end

      test "atom requests are rendered to auth'd users" do
        GistHelpers.generate(user: @priv_user,
          contents: @create_contents, description: "private secrets",
          public: false)

        as @pub_user
        get "/gist/#{@priv_user.display_login}.atom"

        assert_response :success
        assert_template "gists/listings/feed"
        assert_equal "application/atom+xml", response.media_type
        refute_includes response.body, "private secrets"
      end

      test "404's on spammy accounts", skip_unless: :spamminess_check_enabled? do
        @pub_user.update_attribute :spammy, true

        as @priv_user

        get "/gist/#{@pub_user.display_login}"

        assert_response :not_found
        refute_includes response.body, "spammy"
      end

      test "404's with an unknown format" do
        get "/gist/#{@pub_user.display_login}.php"

        assert_response :not_found
      end

      test "404's with an invalid id and unknown format" do
        get "/gist/index.php"

        assert_response :not_found
      end
    end

    context "gists for EMUs", skip_enterprise: true do
      test "404s for a regular user accessing an EMU org gists page" do
        as @pub_user
        get "/gist/#{@emu_org.display_login}"
        assert_response :not_found
      end

      test "404s for an anonymous request accessing an EMU org gists page" do
        get "/gist/#{@emu_org.display_login}"
        assert_response :not_found
      end

      test "404s for an EMU from another Enterprise accessing an EMU org gists page" do
        other_emu_business = create :business, :enterprise_managed
        other_emu_member = create :emu, business: other_emu_business
        as other_emu_member
        get "/gist/#{@emu_org.display_login}"
        assert_response :not_found
      end

      test "succeeds for an EMU accessing an EMU org gists page" do
        as @emu_member
        get "/gist/#{@org.display_login}"
        assert_response :success
      end

      test "succeeds for an EMU viewing a non EMU gists page" do
        as @emu_member
        get "/gist/#{@org.display_login}"
        assert_response :success
      end

      test "EMU gist profiles 404" do
        # block EMU gists per https://github.com/github/repos/issues/3058
        get "/gist/#{@emu_member}"
        assert_response :not_found
      end
    end

    context "as an anonymous user" do
      test "404's on spammy accounts", skip_unless: :spamminess_check_enabled? do
        @pub_user.update_attribute :spammy, true

        get "/gist/#{@pub_user.display_login}"

        assert_response :not_found
        refute_includes response.body, "spammy"
      end
    end

    context "as a site admin", skip_unless: :spamminess_check_enabled? do
      test "allows viewing spammy user with a notice mesage" do
        @pub_user.update_attribute :spammy, true

        as @staff_user

        get "/gist/#{@pub_user.display_login}"

        assert_response :success
        assert_includes response.body, "spammy"
      end
    end
  end

  context "user forked page" do
    context "viewing your page" do
      test "renders" do
        @pub_gist.fork @priv_user
        as @priv_user

        get "/gist/#{@priv_user.display_login}/forked"

        assert_response :success
        assert_template "gists/users/show"
        assert_includes response.body, @pub_gist.description
        assert_includes response.body, "link href=\"/gist/#{@priv_user.display_login}/forked.atom"
      end

      test "atom requests are rendered" do
        @pub_gist.fork @priv_user
        as @priv_user

        get "/gist/#{@priv_user.display_login}/forked.atom"

        assert_response :success
        assert_template "gists/listings/feed"
        assert_equal "application/atom+xml", response.media_type
        assert_includes response.body, @pub_gist.description
      end

      test "404's with an invalid user id" do
        as @pub_user

        get "/gist/made-up-shenanigans/forked"

        assert_response :not_found
      end
    end

    context "viewing someone else's page" do
      test "doesn't show private gists" do
        as @pub_user

        GistHelpers.generate \
          user: @priv_user,
          contents: @create_contents,
          public: false

        assert_equal 0, @priv_user.gists.are_public.count
        assert @priv_user.gists.are_secret.count > 0

        get "/gist/#{@priv_user.display_login}/forked"
        assert_response :success
        refute_includes response.body, "id=\"file-hello-rb-L1\""
        assert_includes response.body, "doesn’t have any forked gists yet"
      end

      test "does not include DMCA'd forks", skip_enterprise: true do
        fork = @pub_gist.fork(@priv_user)
        fork.access.disable("dmca", @staff_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        get "/gist/#{@priv_user.display_login}/forked"

        assert_response :ok
        assert_select "a[href='/gist/#{fork.name_with_display_owner}']", count: 0
      end

      test "spammer's fork page 404s", skip_unless: :spamminess_check_enabled? do
        spammer = create(:user)
        spammy_fork = @pub_gist.fork spammer
        spammer.mark_as_spammy
        spammy_fork.tap(&:set_user_hidden).save!

        get "/gist/#{spammer}/forked"

        assert_response :not_found
      end

      test "lists forks of spammy gists", skip_unless: :spamminess_check_enabled? do
        spammer = create(:user)
        spammy_gist = GistHelpers.generate(user: spammer, contents: @create_contents)
        spammy_gist.fork @pub_user
        spammer.mark_as_spammy
        spammy_gist.tap(&:set_user_hidden).save!

        get "/gist/#{@pub_user.display_login}/forked"

        assert_response :success
        assert_template "gists/users/show"
        assert_select ".gist-snippet", count: 1
        assert_select "a[href='/gist/#{@pub_user.display_login}/forked']", text: /Forked\s+1/
      end


      test "includes forks of spammy gists in atom feed", skip_unless: :spamminess_check_enabled? do
        spammer = create(:user)
        spammy_gist = GistHelpers.generate(user: spammer, contents: @create_contents)
        fork = spammy_gist.fork(@pub_user)
        spammer.mark_as_spammy
        spammy_gist.tap(&:set_user_hidden).save!

        get "/gist/#{@pub_user.display_login}/forked", params: { format: "atom" }

        assert_response :success
        assert_includes response.body, "/gist/#{fork.name_with_display_owner}"
      end
    end
  end

  context "user starred page" do
    context "viewing your page" do
      test "atom requests are rendered" do
        @priv_user.star @pub_gist
        as @priv_user

        get "/gist/#{@priv_user.display_login}/starred.atom"

        assert_response :success
        assert_template "gists/listings/feed"
        assert_equal "application/atom+xml", response.media_type
        assert_includes response.body, @pub_gist.description
      end

      test "404's with an invalid user id" do
        as @pub_user

        get "/gist/made-up-shenanigans/starred"

        assert_response :not_found
      end
    end

    context "viewing someone else's page" do
      test "doesn't show private gists" do
        as @pub_user

        GistHelpers.generate \
          user: @priv_user,
          contents: @create_contents,
          public: false

        assert_equal 0, @priv_user.gists.are_public.count
        assert @priv_user.gists.are_secret.count > 0

        get "/gist/#{@priv_user.display_login}/starred"
        assert_response :success
        refute_includes response.body, "id=\"file-hello-rb-L1\""
        assert_includes response.body, "doesn’t have any starred gists yet"
      end

      test "does not include DMCA'd stars", skip_enterprise: true do
        stargazer = create(:user)
        stargazer.star @pub_gist

        get "/gist/#{stargazer}/starred"
        assert_select "a[href='/gist/#{stargazer}/starred']", text: /Starred\s+1/

        @pub_gist.access.disable("dmca", @staff_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        get "/gist/#{stargazer}/starred"

        assert_response :ok
        assert_select "a[href='/gist/#{@pub_gist.name_with_display_owner}']", count: 0
        assert_select "a[href='/gist/#{stargazer}/starred']", text: /Starred\s+0/
      end

      test "hides spammy gists", skip_unless: :spamminess_check_enabled? do
        stargazer = create(:user)
        stargazer.star @pub_gist
        @pub_gist.user.mark_as_spammy
        @pub_gist.tap(&:set_user_hidden).save!

        as create(:user)
        get "/gist/#{stargazer}/starred"

        assert_response :success
        assert_template "gists/users/show"
        assert_select ".gist-snippet", count: 0
        assert_select "a[href='/gist/#{stargazer}/starred']", text: /Starred\s+0/
      end
    end

    context "viewing as anon" do
      test "hides spammy gists", skip_unless: :spamminess_check_enabled? do
        stargazer = create(:user)
        stargazer.star @pub_gist
        @pub_gist.user.mark_as_spammy
        @pub_gist.tap(&:set_user_hidden).save!

        get "/gist/#{stargazer}/starred"

        assert_response :success
        assert_template "gists/users/show"
        assert_select ".gist-snippet", count: 0
      end
    end
  end
end
