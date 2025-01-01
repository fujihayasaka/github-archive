# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerUpdateGistHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  include HydroTestHelpers
  extend GistsControllerTestSetup

  skip_with_all_emus

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures(&fixtures_block)
  setup(&global_setup_block(enable_spokesd: false))

  setup do
    # disable cache for update tests which compare
    # before and after values by looking at Gist#files directly
    disable_cache_storage

    GitHub.flipper[:notifications_async_gist_subscription_button].disable
  end

  teardown do
    GitRepositoryBlock.expire_country_block_cache
  end

  context "updating a gist" do
    test "works as owner" do
      as @pub_user

      contents = @update_contents.dup
      contents.first[:value] = "NEW-VALUE"

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }

      assert_response 302

      updated_file = @pub_gist.files.find { |f| f.name == contents.first[:name] }

      refute_includes updated_file.data, "### HEADER"
      assert_includes updated_file.data, "NEW-VALUE"
    end

    context "Windows newlines" do
      test "removes Window newlines in new files" do
        as @pub_user

        contents = @update_contents.map { |o| o }
        contents << { name: "new-file.txt", value: "a new file \r\n" }

        put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }

        new_file = @pub_gist.files.find { |f| f.name == "new-file.txt" }
        assert_includes new_file.data, "a new file \n"
      end

      test "preserves Windows newlines if they were already present" do
        as @pub_user

        original_value = "windows line ending \r\n"
        contents = [{ name: "window-file.txt", value: original_value }]
        creator = Gist::Creator.new(public: true, user: @pub_user, contents: contents)

        # mimic a scenario in which a file might have been created with windows line endings,
        # e.g. when created via API request.
        creator.gist.preserve_line_endings = true
        creator.create
        gist = creator.gist

        updated_contents = [{ name: "window-file.txt",  value: "#{original_value} also, hi" }]

        put gist_url_for(gist), params: { gist: { "contents" => updated_contents } }

        updated_file = gist.files.first.data
        assert_includes(updated_file, "windows line ending \r\n also, hi")
      end
    end

    test "works with unicode files as owner" do
      as @unicode_user

      new_value = "同局技員載額探陸住断否必掲名江表。設普房受芸費度善上考競領外。級立京村落別"
      contents = @update_unicode_contents.dup
      contents.first[:value] = new_value
      contents.first[:oid] = @unicode_gist.files.first.oid

      put gist_url_for(@unicode_gist), params: { gist: { "contents" => contents } }

      assert_response 302
      updated_file = @unicode_gist.files.first.data
      refute_includes updated_file, "my content"
      assert_includes updated_file, new_value
    end

    test "autogenerates filenames correctly" do
      as @pub_user

      contents = [{ name: "", value: "NEW-VALUE" }]
      gist = GistHelpers.generate user: @pub_user, contents: contents
      assert_equal 1, gist.files.count
      file = gist.files.first
      assert_equal "gistfile1.txt", file.name

      # Add another unnamed file
      contents = [{ name: "", value: "OTHER-VALUE" }]
      contents << { name: file.name, value: file.data, oid: file.oid }

      put gist_url_for(gist), params: { gist: { "contents" => contents } }

      assert_equal 2, gist.reload.files.count
      assert_equal "gistfile1.txt", gist.files.first.name

      filenames = gist.files.map { |f| f.name }.sort
      assert_equal ["gistfile1.txt", "gistfile2.txt"], filenames
    end

    test "increments the pushed counts" do
      as @pub_user
      contents = @update_contents.dup
      contents.first[:value] = "PushIt"

      assert_equal 0, @pub_gist.pushed_count
      assert_equal 0, @pub_gist.pushed_count_since_maintenance

      # NOTE: assert_difference with a RockQueue.inline block was not working
      perform_enqueued_jobs(only: [GistPushJob]) do
        put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }
      end

      @pub_gist.reload

      assert_equal 1, @pub_gist.pushed_count
      assert_equal 1, @pub_gist.pushed_count_since_maintenance
    end

    test "employess cannot update someone else's gist" do
      as @staff_user

      contents = @update_contents.dup
      contents.first[:value] = "NEW-VALUE"

      commit_count = @pub_gist.commits.history(@pub_gist.sha).count

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }

      assert_equal @pub_gist.commits.history(@pub_gist.sha).count, commit_count
      assert_response 404
    end

    test "adding a file" do
      as @pub_user

      contents = @update_contents.dup
      contents << { name: "newfile.md", value: "WEEE" }

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }

      assert_response 302
      assert_includes @pub_gist.files.map(&:name), "newfile.md"
    end

    test "deleting a file" do
      as @pub_user

      contents = @update_contents.dup
      contents << { name: "newfile.md", value: "WEEE" }

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }
      assert_response 302

      names = @pub_gist.files.map(&:name)
      assert_includes names, "newfile.md"
      assert_includes names, "hello.rb"

      newfile_md = @pub_gist.files.detect { |f| f.name == "newfile.md" }
      contents.last[:oid] = newfile_md.oid
      contents.last[:delete] = true

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }
      assert_response 302

      names = @pub_gist.files.map(&:name)
      refute_includes names, "newfile.md"
      assert_includes names, "hello.rb"
    end

    test "renaming a file" do
      as @pub_user

      contents = @update_contents.dup
      contents.first[:name] = "totally-new-name.md"

      put gist_url_for(@pub_gist), params: { gist: { "contents" => contents } }

      assert_response 302

      names = @pub_gist.files.map(&:name)
      refute_includes names, "hello.rb"
      assert_includes names, "totally-new-name.md"
    end

    test "gist update event published to hydro" do
      SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
      GitHub.stubs(:hydro_enabled?).returns(true)
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        as @pub_user

        gist = GistHelpers.generate(user: @pub_user,
                                 contents: @create_contents,
                                 description: @pub_gist_description)

        previous_head_sha = gist.sha
        serialized_previous_gist = Hydro::EntitySerializer.gist(gist)
        serialized_previous_files = Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files))

        new_contents = [
          { name: "file1", value: "text" },
          { name: "file2", value: "another" },
        ]

        put gist_url_for(gist), params: { gist: { "contents" => new_contents } }

        gist.reload

        message = {
          actor: Hydro::EntitySerializer.user(@pub_user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          previous_gist: serialized_previous_gist,
          current_gist: Hydro::EntitySerializer.gist(gist),
          previous_head_sha: previous_head_sha,
          current_head_sha: gist.sha,
          previous_files: serialized_previous_files,
          current_files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
          specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
          specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
          specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
          feature_flags: [],
        }

        assert_hydro_published(message, schema: "github.v1.GistUpdate")
      end
    end

    test "failed update doesn't lose user content" do
      as @pub_user

      contents = @update_contents.dup
      contents << { "name" => "newfile.md", "value" => "WEEE" }

      desc_that_is_too_long = "漢" * 2048
      put gist_url_for(@pub_gist), params: { gist: {
        "description" => desc_that_is_too_long,
        "contents" => contents,
      } }
      assert_select ".flash.flash-error", "Description is too long (maximum is 256 characters)"

      assert_includes response.body, "WEEE"
      assert_includes response.body, "newfile.md"
    end

    test "failed update re-renders utf filenames correctly" do
      as @unicode_user

      contents = @update_unicode_contents
      desc_that_is_too_long = "漢" * 2048

      put gist_url_for(@unicode_gist), params: { gist: {
        "description" => desc_that_is_too_long,
        "contents" => contents,
      } }

      assert_select ".flash.flash-error", "Description is too long (maximum is 256 characters)"
      assert_includes response.body, "房子.txt"
    end
  end

  context "updating a gist file tasklist" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @task_list_contents = [
        { name: "hello.md", value: "### HI!\n\n - [ ] aaa\n- [ ] bbb\n- [ ] ccc" },
      ]
      @task_list_gist = GistHelpers.generate(user: @pub_user, contents: @task_list_contents)
      @hello_oid = @task_list_gist.files.first.oid
    end

    test "works for the author" do
      as @pub_user

      content = @task_list_contents.first[:value].gsub("- [ ] aaa", "- [x] aaa")

      put gist_url_for(@task_list_gist, path_segment: "/file/#{@hello_oid}"), params: { gist: { "content" => content }, task_list_track: "checked:1", task_list_key: "gist" }

      assert_response 302

      updated_file = @task_list_gist.files.first
      assert updated_file.data.include?("- [x] aaa"), "Expected #{updated_file.name} to include '- [x] aaa', but instead content was #{updated_file.data}"
    end

    test "ajax response includes URL with updated blob OID" do
      as @pub_user

      put gist_url_for(@task_list_gist, path_segment: "/file/#{@hello_oid}"), params: { gist: { "content" => "hello" } }, xhr: true

      assert_response :success

      hello_world = @task_list_gist.reload.files.find { |f| f.name == "hello.md" }
      refute_equal hello_world.oid, @hello_oid

      json = JSON.parse(response.body)
      assert_includes json["url"], update_user_gist_file_path(@task_list_gist.user_param, @task_list_gist, hello_world.oid)
    end

    test "updating someone else's task list as staff doesn't change owner" do
      as @priv_staff_user
      owner = @task_list_gist.owner

      content = @task_list_contents.first[:value].gsub("- [ ] aaa", "- [x] aaa")

      put gist_url_for(@task_list_gist, path_segment: "/file/#{@hello_oid}"), params: { gist: { "content" => content }, task_list_track: "checked:1", task_list_key: "gist" }

      assert_equal @task_list_gist.reload.owner, owner
    end
  end

  context "toggling a gist's visibility" do
    test "works as owner" do
      as @pub_user

      assert_equal @secret_gist.visibility, "secret"

      put gist_url_for(@secret_gist, path_segment: "make_public")

      assert_redirected_to gist_url_for(@secret_gist)
      assert_equal @secret_gist.reload.visibility, "public"
    end

    test "gist update event published to hydro" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      SecretScanning::Instrumentation::GistServiceFlags.any_instance.stubs(:gist_scanning_service_flags).returns([])
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        as @pub_user

        gist = GistHelpers.generate(user: @pub_user,
                                    contents: @create_contents,
                                    public: false,
                                    description: "description")

        previous_head_sha = gist.sha
        serialized_previous_gist = Hydro::EntitySerializer.gist(gist)
        serialized_previous_files = Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files))

        put gist_url_for(gist, path_segment: "make_public")

        gist.reload

        message = {
          actor: Hydro::EntitySerializer.user(@pub_user),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          previous_gist: serialized_previous_gist,
          current_gist: Hydro::EntitySerializer.gist(gist),
          previous_head_sha: previous_head_sha,
          current_head_sha: gist.sha,
          previous_files: serialized_previous_files,
          current_files: Hydro::EntitySerializer.gist_files(gist, Gist.limit_files(gist.files)),
          specimen_files: Hydro::EntitySerializer.gist_specimen_files(Gist.limit_files(gist.files).first(3)),
          specimen_gist_description: Hydro::EntitySerializer.specimen_data(gist.description),
          specimen_files_path: Hydro::EntitySerializer.gist_specimen_files_path(Gist.limit_files(gist.files).first(3)),
          feature_flags: [],
        }

        assert_hydro_published(message, schema: "github.v1.GistUpdate")
      end
    end

    test "updating someone else's gist doesn't work" do
      as create(:user)

      assert_equal @secret_gist.visibility, "secret"

      put gist_url_for(@secret_gist, path_segment: "make_public")

      assert_equal @secret_gist.reload.visibility, "secret"
    end

    unless GitHub.enterprise?
      test "works for trade controls restricted gists" do
        assert_equal @secret_gist.visibility, "secret"

        @pub_user.trade_controls_restriction.full!

        as @pub_user
        put gist_url_for(@secret_gist, path_segment: "make_public")

        assert_redirected_to gist_url_for(@secret_gist)
        assert_equal @secret_gist.reload.visibility, "public"
      end
    end
  end

  context "revisions page" do
    test "renders" do
      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user

      get gist_url_for(@pub_gist, path_segment: "revisions")

      assert_response :success
      assert_template "gists/gists/revisions"
      etag = ActiveSupport::Digest.hexdigest(ActiveSupport::Cache.expand_cache_key(@pub_gist.viewer_cache_key(@pub_user)))
      assert_equal %("#{etag}"), @response.headers["ETag"]
      assert_includes response.body, "hello.rb"
    end

    unless GitHub.enterprise?
      test "cannot show gist disabled for dmca" do
        @pub_gist.access.disable("dmca", @pub_user, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

        as @pub_user

        get gist_url_for(@pub_gist, path_segment: "revisions")

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
          "Reason for country block"
        )
        get gist_url_for(@pub_gist, path_segment: "revisions")
        assert_response 200
        assert_template "gists/gists/revisions"
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
          "Reason for country block"
        )
        get gist_url_for(@pub_gist, path_segment: "revisions")

        assert_response 200
        assert_template "gists/gists/revisions"
      end

      test "cannot show a gist with country block for blocked country" do
        request_env["HTTP_X_COUNTRY"] = "RU"
        as @pub_user

        @pub_gist.access.country_block(
          @pub_user,
          GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
          "https://github.com/github/nation-state-blocks/blob/master/2011/2011-01-27-sony.markdown",
          "Reason for country block"
        )
        get gist_url_for(@pub_gist, path_segment: "revisions")

        assert_response 200
        assert_template "gists/gists/states/nation_blocklist"
      end

      test "shows secret gist notice with make public option for trade restriceted owner" do
        assert_equal @secret_gist.visibility, "secret"
        @pub_user.trade_controls_restriction.full!

        as @pub_user
        get gist_url_for(@secret_gist, path_segment: "revisions")

        assert_includes response.body, TradeControls::Notices.secret_gist_restricted
        assert_includes response.body, "Make public"
      end

      test "shows secret gist notice without make public option for trade restriceted user" do
        user = create(:user)
        assert_equal @secret_gist.visibility, "secret"
        user.trade_controls_restriction.full!

        as user
        get gist_url_for(@secret_gist, path_segment: "revisions")

        assert_includes response.body, TradeControls::Notices.secret_gist_restricted
        refute_includes response.body, "Make public"
      end
    end
  end

  context "download redirect" do
    test "works" do
      as @pub_user
      get gist_url_for(@pub_gist, path_segment: "download")

      assert_response 302
      assert_redirected_to "https://codeload.github.com/gist/#{@pub_gist.to_param}/zip/main"
    end
  end
end
