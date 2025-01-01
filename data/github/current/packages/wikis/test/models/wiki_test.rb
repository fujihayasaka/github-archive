# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class UnsulliedWikiTestBase < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    Spokesd.enable_spokesd
    @user = build(:user)
    @user.protocols = { "push" => "ssh", "clone" => "gitweb" }
    @user.save!

    @collaborator = create(:user)

    @repo = create(:repository)
    @repo.add_member(@collaborator)

    @repo2 = create(:repository)

    @private_repo = create(:private_repository)
  end

  setup do
    Spokesd.enable_spokesd
    @repo.initialize_wiki(@repo.owner)
    @wiki = @repo.unsullied_wiki

    @repo2.initialize_wiki(@repo.owner)
    @empty_wiki = @repo2.unsullied_wiki

    enable_cache_storage

    example_repo :wiki, @wiki

    reset_cache
  end
end

class UnsulliedWikiTest < UnsulliedWikiTestBase
  test "empty wiki repos have no revisions" do
    assert_equal [], @empty_wiki.revisions
    assert_equal 0, @empty_wiki.revision_count
  end

  test "#submodule returns nil" do
    assert_nil @empty_wiki.submodule("any number", "of args")
  end

  if GitHub.spamminess_check_enabled?
    test "spammy user can't create a wiki page" do
      @user.mark_as_spammy

      name = "new page"
      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        @wiki.pages.create name, :markdown, "new", "initial #{name}", @user
      end
    end

    test "spammy user can't edit a wiki page" do
      @user.mark_as_spammy

      page = @wiki.pages.find("edit-me")
      error = assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.update(page.name, "edited!", page.format, "boom", @user)
      end
      assert_equal "Spammy users cannot edit wiki pages they don't own", error.message
    end

    test "spammy user can't revert changes to a wiki page" do
      @user.mark_as_spammy

      page = @wiki.pages.find("edit-me")
      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.revert("deadbeef", "deadbeef2", @user)
      end
    end

    test "spammy user can't delete wiki pages" do
      @user.mark_as_spammy

      page = @wiki.pages.find("edit-me")
      error = assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.remove(@user)
      end
      assert_equal "Spammy users cannot delete wiki pages they don't own", error.message
    end
  end

  if GitHub.email_verification_enabled?
    test "unverified user can't create a wiki page" do
      @user.stubs(:must_verify_email?).returns(true)

      name = "new page"
      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        @wiki.pages.create name, :markdown, "new", "initial #{name}", @user
      end
    end

    test "unverified user can't edit a wiki page" do
      @user.stubs(:must_verify_email?).returns(true)

      page = @wiki.pages.find("edit-me")
      error = assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.update(page.name, "edited!", page.format, "boom", @user)
      end
      assert_match /email address must be verified/, error.message
    end

    test "unverified user can't revert changes to a wiki page" do
      @user.stubs(:must_verify_email?).returns(true)

      page = @wiki.pages.find("edit-me")
      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.revert("deadbeef", "deadbeef2", @user)
      end
    end

    test "unverified user can't delete wiki pages" do
      @user.stubs(:must_verify_email?).returns(true)

      page = @wiki.pages.find("edit-me")
      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        page.remove(@user)
      end
    end
  end

  test "revision_count works with corrupt commits" do
    begin
      broken_wiki = @repo.unsullied_wiki(true)
      broken_head = broken_wiki.refs.find("broken-commit").target_oid
      homepage = broken_wiki.pages.find("Home", broken_head)
      assert_equal 2, homepage.revision_count(broken_head)
    rescue GitRPC::BadObjectState
      raised = true
    ensure
      assert !raised, "raised GitRPC::BadObjectState but didn't expect it to"
    end
  end

  test "#path is nested under repo path" do
    assert_equal "#{@repo.owner}/#{@repo}.wiki.git", @wiki.path
  end

  test "#short_git_path is nested under repo path" do
    assert_equal "#{@repo.owner}/#{@repo}.wiki", @wiki.short_git_path
  end

  test "#base_path is nested under repo path" do
    assert_equal "/#{@repo.owner}/#{@repo}/wiki", @wiki.base_path
  end

  test "sorts pages by latest date" do
    pages = @wiki.pages.latest
    assert_equal %w[windows-utf16 windows edit-me expendable home], pages.map(&:name)
  end

  test "latest pages have their revision_oid set" do
    pages = @wiki.pages.latest
    pages.each do |page|
      assert !page.revision_oid.nil?
    end
  end

  test "page title" do
    page = @wiki.pages.find("home")
    assert_equal "home", page.title # checks the blob
  end

  test "can't create new page without a primary email" do
    UserEmail.where(user_id: @repo.owner.id).delete_all
    @repo.owner.reload
    refute @repo.owner.has_primary_email?

    name = "new-page"
    assert_raises GitHub::Unsullied::Wiki::Error do
      @wiki.pages.create name, :markdown, "new", "initial #{name}", @repo.owner
    end
  end

  test "cannot create a page with a path-traversing .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "../../something/evil.git"]
        path = totally-innocent
        url = foo
    GITMODULES

    assert_raises(GitRPC::BadGitmodules) do
      @wiki.pages.create ".gitmodules", :plain, gitmodules_content, "somepage", @repo.owner
    end
  end

  test "cannot create a page with an option-injecting url in .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = -u./payload
    GITMODULES

    assert_raises(GitRPC::BadGitmodules) do
      @wiki.pages.create ".gitmodules", :plain, gitmodules_content, "somepage", @repo.owner
    end
  end

  test "cannot create a page with an option-injecting path in .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = -what
        url = https://example.com/innocent.git
    GITMODULES

    assert_raises(GitRPC::BadGitmodules) do
      @wiki.pages.create ".gitmodules", :plain, gitmodules_content, "somepage", @repo.owner
    end
  end

  test "cannot create a page with a URL injecting into the credential helper in .gitmodules file" do
    gitmodules_content = <<-GITMODULES
      [submodule "evil"]
        path = totally-innocent
        url = https://example.com/evil?%0ahost=github.com
    GITMODULES

    assert_raises(GitRPC::BadGitmodules) do
      @wiki.pages.create ".gitmodules", :plain, gitmodules_content, "somepage", @repo.owner
    end
  end

  test "can't update page without a primary email" do
    UserEmail.where(user_id: @repo.owner.id).delete_all
    @repo.owner.reload
    refute @repo.owner.has_primary_email?

    page = @wiki.pages.find("edit-me")
    assert_raises GitHub::Unsullied::Wiki::Error do
      page = page.update(page.name, "edited!", page.format, "boom", @repo.owner)
    end
  end

  test "can't remove page without a primary email" do
    UserEmail.where(user_id: @repo.owner.id).delete_all
    @repo.owner.reload
    refute @repo.owner.has_primary_email?

    page = @wiki.pages.find("edit-me")
    assert_raises GitHub::Unsullied::Wiki::Error do
      page = page.remove(@repo.owner)
    end
  end

  test "gets last author of a page" do
    page = @wiki.pages.find("home")
    assert_equal "rick", page.latest_revision.author_name
  end

  test "owner can write to public wiki with world-writable access" do
    @repo.world_writable_wiki = true
    assert @repo.wiki_writable_by?(@repo.owner)
  end

  test "collaborator can write to public wiki with world-writable access" do
    @repo.world_writable_wiki = true
    assert @repo.wiki_writable_by?(@collaborator)
  end

  test "user can write to public wiki with world-writable access" do
    @repo.world_writable_wiki = true
    assert @repo.wiki_writable_by?(@user)
  end

  test "owner can write to public wiki with collaborator access" do
    @repo.world_writable_wiki = false
    assert @repo.wiki_writable_by?(@repo.owner)
  end

  test "collaborator can write to public wiki with collaborator access" do
    @repo.world_writable_wiki = false
    assert @repo.wiki_writable_by?(@collaborator)
  end

  test "user cannot write to public wiki with collaborator access" do
    @repo.world_writable_wiki = false
    assert !@repo.wiki_writable_by?(@user)
  end

  test "owner can write to private wiki with world-writable access" do
    @repo.world_writable_wiki = true
    @repo.public = false
    assert @repo.wiki_writable_by?(@repo.owner)
  end

  test "collaborator can write to private wiki with world-writable access" do
    @repo.world_writable_wiki = true
    @repo.public = false
    assert @repo.wiki_writable_by?(@collaborator)
  end

  test "user cannot write to private wiki with world-writable access" do
    @repo.world_writable_wiki = true
    @repo.public = false
    assert !@repo.wiki_writable_by?(@user)
  end

  test "owner can write to private wiki with collaborator access" do
    @repo.world_writable_wiki = false
    @repo.public = false
    assert @repo.wiki_writable_by?(@repo.owner)
  end

  test "collaborator can write to private wiki with collaborator access" do
    @repo.world_writable_wiki = false
    @repo.public = false
    assert @repo.wiki_writable_by?(@collaborator)
  end

  test "user cannot write to private wiki with collaborator access" do
    @repo.world_writable_wiki = false
    @repo.public = false
    assert !@repo.wiki_writable_by?(@user)
  end

  test "#wiki_world_writable? is false for private repos" do
    @repo.world_writable_wiki = true
    @repo.public = false
    assert !@repo.wiki_world_writable?
  end

  test "#wiki_world_writable? is false for repos with collaborator access wikis" do
    @repo.world_writable_wiki = false
    @repo.public = true
    assert !@repo.wiki_world_writable?
  end

  test "#wiki_world_writable? is true for public repos with full wiki access" do
    @repo.world_writable_wiki = true
    @repo.public = true
    assert @repo.wiki_world_writable?
  end

  test "picks user push protocol" do
    selector(@user)
    assert_equal "ssh", selector.push_protocol
    assert_equal @wiki.ssh_url, selector.push_url
  end

  test "picks user clone protocol" do
    selector(@user)
    assert_equal "gitweb", selector.clone_protocol
    assert_equal @wiki.gitweb_url, selector.clone_url
  end

  test "picks default with invalid user preferences" do
    @user.protocols["push"] = "abc"
    assert_equal "http", selector(@user).push_protocol
  end

  test "picks default push protocol" do
    assert_equal "http", selector.clone_protocol
    assert_equal @wiki.http_url, selector.clone_url
  end

  def selector(user = nil)
    @selector ||= @wiki.protocol_selector(user)
  end

  test "wikis support up to 5000 pages" do
    repo = create(:repository)
    repo.initialize_wiki(repo.owner)
    wiki = repo.unsullied_wiki

    # this repo has 5001 files in it
    example_repo :wiki_large_list, wiki

    assert_equal 5000, wiki.pages.count
  end

  test "wiki page's have sidebars based on their parent directory" do
    repo = create(:repository)
    repo.initialize_wiki(repo.owner)
    wiki = repo.unsullied_wiki

    example_repo :wiki_with_subdirs, wiki

    # /Home.md and /_Sidebar.md
    root_page = wiki.pages.find("home")
    assert_equal root_page.dirname, root_page.sidebar.dirname
    assert_equal "root sidebar", root_page.sidebar.data.rstrip

    # /subdir/SubPage.md and /subdir/_Sidebar.md
    sub_page = wiki.pages.find("SubPage")
    assert_equal sub_page.dirname, sub_page.sidebar.dirname
    assert_equal "subdir sidebar", sub_page.sidebar.data.rstrip

    # /subdir-without-sidebar/AnotherPage.md and /_Sidebar.md
    # sidebars apply to all nested subdirs that don't have sidebars
    another_page = wiki.pages.find("AnotherPage")
    assert_equal root_page.dirname, another_page.sidebar.dirname
    assert_equal "root sidebar", another_page.sidebar.data.rstrip

    # /subdir/another-subdir/maddox.md and /subdir/another-subdir/_Sidebar.md
    maddox = wiki.pages.find("maddox")
    assert_equal maddox.dirname, maddox.sidebar.dirname
    assert_equal "sidebar two levels deep", maddox.sidebar.data.rstrip
  end

  test "wiki page's have footers based on their parent directory" do
    repo = create(:repository)
    repo.initialize_wiki(repo.owner)
    wiki = repo.unsullied_wiki

    example_repo :wiki_with_subdirs, wiki

    # /Home.md and /_Footer.md
    root_page = wiki.pages.find("home")
    assert_equal root_page.dirname, root_page.footer.dirname
    assert_equal "root footer", root_page.footer.data.rstrip

    # /subdir/SubPage.md and /subdir/_Footer.md
    sub_page = wiki.pages.find("SubPage")
    assert_equal sub_page.dirname, sub_page.footer.dirname
    assert_equal "subdir footer", sub_page.footer.data.rstrip

    # /subdir-without-sidebar/AnotherPage.md and /_Footer.md
    # sidebars apply to all nested subdirs that don't have sidebars
    another_page = wiki.pages.find("AnotherPage")
    assert_equal root_page.dirname, another_page.footer.dirname
    assert_equal "root footer", another_page.footer.data.rstrip

    # /subdir/another-subdir/maddox.md and /subdir/another-subdir/_Footer.md
    maddox = wiki.pages.find("maddox")
    assert_equal maddox.dirname, maddox.footer.dirname
    assert_equal "footer two levels deep", maddox.footer.data.rstrip
  end

  context "data_html" do
    test "returns a struct" do
      page = @wiki.pages.find("edit-me")
      data = page.data_html
      refute data.errored?
      refute data.timed_out?
      assert_includes data.to_s, %(<p>edit me</p>)
    end

    test "keeps information about timeout" do
      Failbot.expects(:report).never

      page = @wiki.pages.find("edit-me")
      page.expects(:data_utf8).raises(Timeout::Error)
      data = page.data_html
      assert data.errored?
      assert data.timed_out?
      assert_equal %{<p>Sorry, there was an error rendering this page.</p>}, data.to_s
    end

    test "handles rendering invalid syntax" do
      page = GitHub::Unsullied::Page.new(@wiki, {
        "path" => "Neat-ideas.pod",
        "data" => "Wait...this isn't valid POD syntax.",
      })
      data = page.data_html
      refute data.errored?
      refute data.timed_out?
      assert_equal "Wait...this isn't valid POD syntax.", data.to_s
    end

    test "can be cached" do
      page = GitHub::Unsullied::Page.new(@wiki, {
        "path" => "Neat-ideas.pod",
        "data" => "Wait...this isn't valid POD syntax.",
      })
      data = page.data_html
      packed = GitHub::Cache::Codec.factory.pack(data)

      assert_equal data.html, GitHub::Cache::Codec.unpack(packed).html
      assert data.html.html_safe?
      assert GitHub::Cache::Codec.unpack(packed).html.html_safe?
    end

    test "can be cached for an error" do
      page = GitHub::Unsullied::Page.new(@wiki, {
        "path" => "Neat-ideas.pod",
        "data" => "Wait...this isn't valid POD syntax.",
      })
      page.expects(:data_utf8).raises(Timeout::Error)
      data = page.data_html
      assert data.errored?
      assert data.timed_out?

      packed = GitHub::Cache::Codec.factory.pack(data)
      unpacked = GitHub::Cache::Codec.unpack(packed)
      assert_equal data.html, unpacked.html
      assert unpacked.errored?
      assert unpacked.timed_out?
    end

    test "reports non-timeout errors to failbot" do
      Failbot.expects(:report).once

      page = @wiki.pages.find("edit-me")
      page.expects(:data_utf8).raises(StandardError)
      data = page.data_html
      assert data.errored?
      refute data.timed_out?
      assert_equal %{<p>Sorry, there was an error rendering this page.</p>}, data.to_s
    end
  end

  class SetupGitRepositoryTest < GitHub::TestCase
    fixtures do
      @repo = create(:repository)
    end

    def assert_routes(repo, for_wiki = true)
      assert repo.unsullied_wiki.exist? if for_wiki
      assert_equal GitHub.dgit_default_copies, GitHub::DGit::Routing.all_repo_replicas(repo.id, for_wiki).count
      refute_nil for_wiki ? GitHub::DGit::Routing.wiki_checksum(repo.network.id, repo.id) : GitHub::DGit::Routing.repo_checksum(repo.network.id, repo.id)
    end

    def refute_routes(repo, for_wiki = true)
      refute repo.unsullied_wiki.exist? if for_wiki
      assert_equal 0, GitHub::DGit::Routing.all_repo_replicas(repo.id, for_wiki).count
      assert_nil for_wiki ? GitHub::DGit::Routing.wiki_checksum(repo.network.id, repo.id) : GitHub::DGit::Routing.repo_checksum(repo.network.id, repo.id)
    end

    def assert_no_new_replica_and_checksum_rows(network_id, repo_id)
      rr_before = ::DGit.get_repo_replica_ids(network_id, repo_id).length
      rc_before = ::DGit.get_repo_replica_checksums(network_id, repo_id).length
      yield
      assert_equal rr_before, ::DGit.get_repo_replica_ids(network_id, repo_id).length
      assert_equal rc_before, ::DGit.get_repo_replica_checksums(network_id, repo_id).length
    end

    context "#setup_git_repository" do
      test "creates repository replicas, checksums and initializes repo on disk" do
        refute_routes(@repo)
        @repo.unsullied_wiki.setup_git_repository
        @repo.reload
        assert_routes(@repo)
      end

      test "reverts repository replica creation for GitRPC::Error" do
        # just to ensure other repos and their wikis are not affected
        other_repo = create(:repository)
        other_repo.unsullied_wiki.setup_git_repository
        assert_routes(other_repo)
        assert_routes(other_repo, false)
        assert_no_new_replica_and_checksum_rows(@repo.network_id, @repo.id) do
          GitRPC::Client.any_instance.stubs(:ensure_initialized).raises(GitRPC::Error)
          assert_raises(GitRPC::Error) { @repo.unsullied_wiki.setup_git_repository }
        end
        assert_no_new_replica_and_checksum_rows(other_repo.network_id, other_repo.id) do
          GitRPC::Client.any_instance.stubs(:ensure_initialized).raises(GitRPC::Error)
          assert_raises(GitRPC::Error) { @repo.unsullied_wiki.setup_git_repository }
        end
        assert_routes(other_repo)
        assert_routes(other_repo, false)
      end

      test "reverts repository replica creation for GitHub::DGit::Error" do
        assert_no_new_replica_and_checksum_rows(@repo.network_id, @repo.id) do
          GitHub::DGit::Maintenance.stubs(:recompute_checksums).raises(GitHub::DGit::Error)
          assert_raises(GitHub::DGit::Error) { @repo.unsullied_wiki.setup_git_repository }
        end
      end
    end
  end
end

class UnsulliedWikiTransactionalTest < UnsulliedWikiTest
  test "creates new page" do
    name = "newPage"
    sha = @wiki.pages.create name, :markdown, "new", "initial #{name}", @repo.owner
    assert page = @wiki.pages.find(name)
    assert_equal "initial #{name}", page.latest_revision.message
    assert_equal @repo.owner.login, page.latest_revision.author_name
    assert_equal @repo.owner.email, page.latest_revision.author_email
    assert_equal "new",             page.data
  end

  test "page markup linkifies anchors" do
    name = "aPage"
    sha  = @wiki.pages.create name, :markdown, "# A Page", "initial #{name}", @repo.owner

    assert_match /id="user-content-a-page"/, @wiki.pages.find(name).data_html.to_s
  end

  test "page markup marks custom ids as user-content" do
    name = "aPage"
    sha  = @wiki.pages.create name, :markdown, "<a id=\"my-content\">Hi</a>", "initial #{name}", @repo.owner

    assert_match /id="user-content-my-content"/, @wiki.pages.find(name).data_html.to_s
    refute_match /id="my-content"/, @wiki.pages.find(name).data_html.to_s
  end

  test "page markup filters the target attribute" do
    name = "aPage"
    sha  = @wiki.pages.create name, :markdown, '<a href="example.com" target="_blank">Click me!</a>', "initial #{name}", @repo.owner

    assert_not_match /target="/, @wiki.pages.find(name).data_html.to_s
  end

  test "updates page" do
    page = @wiki.pages.find("edit-me")
    page = page.update(page.name, "edited!", page.format, "boom", @repo.owner)


    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: page.latest_revision.oid }],
      pushed_at: Time.current,
      pusher: @repo.owner_login,
      path: @repo.shard_path.sub(".git", ".wiki.git")
    }
    perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_wikis_on_push")

    assert page = @wiki.pages.find("edit‐me")

    assert_equal "boom",            page.latest_revision.message
    assert_equal @repo.owner.login, page.latest_revision.author_name
    assert_equal @repo.owner.email, page.latest_revision.author_email
    assert_equal "edited!",         page.data
  end

  test "updating a title with blank string doesn't change the title" do
    page = @wiki.pages.find("edit-me")
    original_page_name = page.name
    page = page.update("", "edited!", page.format, "boom", @repo.owner)

    assert !page.nil?
    assert_equal "edited!", page.data

    assert_equal "edit‐me", page.name
  end

  test "deletes page" do
    # assert cache is cleared
    s    = "fae1a6268095ac084f0e4482080a23a04b53b54a"
    page = @wiki.pages.find("expendable")
    assert @wiki.pages.latest.find { |p| p.name == "expendable" }

    # assert job is queued
    page = @wiki.pages.find("expendable")

    # check commit
    sha    = page.remove(@repo.owner, "boom!")
    commit = @wiki.commits.find(sha)
    assert_equal "boom!",           commit.message
    assert_equal @repo.owner.login, commit.author_name
    assert_equal @repo.owner.email, commit.author_email
    assert_nil @wiki.pages.find("expendable")
  end

  test "wiki links on the home page are prefixed with wiki" do
    page = @wiki.pages.find "home"
    page = page.update(page.name, "[Foo](Bar)", page.format, "update #{page.name}", @repo.owner)

    assert_match /href=\"wiki\/Bar\"/, page.data_html(prefix_relative_links: true).to_s
  end

  test "non-wiki links aren't wiki linked" do
    page = @wiki.pages.find "home"

    page = page.update(page.name, "[[Bar]]", page.format, "update #{page.name}", @repo.owner)
    assert_match /<a/, page.data_html.to_s

    page = page.update(page.name, "`[[` Bar `]]` and `[[ [\(\)[\]] ]]`", page.format, "update #{page.name}", @repo.owner)
    refute_match /<a/, page.data_html.to_s
  end

  test "external links and anchros on the home page are not prefixed with wiki" do
    page = @wiki.pages.find "home"
    page = page.update(page.name,
      "[Foo](wiki/Foo)\n[github](/github/github)\n[google](http://google.com)\n[section](#section)",
      page.format, "update #{page.name}", @repo.owner)

    html = page.data_html.to_s

    assert_match /href=\"wiki\/Foo\"/, html
    assert_match /href=\"\/github\/github\"/, html
    assert_match /href=\"http:\/\/google\.com\"/, html
    assert_match /href=\"#section\"/, html
  end

  test "wiki sub page links are relative" do
    name = "subPage"
    sha  = @wiki.pages.create name, :markdown, "[Foo](Bar)", "initial #{name}", @repo.owner

    assert_match /href=\"Bar\"/, @wiki.pages.find(name).data_html.to_s
  end

  test "wiki tags have links marked nofollow" do
    name = "relSubPage"
    sha  = @wiki.pages.create name, :markdown, 'test <a href="https://google.com">click me</a>', "initial #{name}", @repo.owner

    assert_match /<a href="https:\/\/google.com" rel="nofollow">click me<\/a>/, @wiki.pages.find(name).data_html.to_s
  end

  test "wiki tags can't overwrite the `rel` attribute" do
    name = "relSubPage"
    sha  = @wiki.pages.create name, :markdown, 'test <a href="https://google.com" rel="facebox">click me</a>', "initial #{name}", @repo.owner

    assert_match /<a href="https:\/\/google.com" rel="nofollow">click me<\/a>/, @wiki.pages.find(name).data_html.to_s
  end

  test "wiki page titles aren't html-escaped" do
    page = @wiki.pages.create "Brooks & Dunn", :markdown, "blah blah blah", "name testing", @repo.owner
    assert_equal "Brooks & Dunn", page.title
  end

  test "wiki page filenames with slashes are sanitized before save" do
    page = @wiki.pages.create "Brooks/Dunn", :markdown, "blah blah blah", "name testing", @repo.owner
    assert_equal "Brooks-Dunn", page.name
  end

  test "gracefully fails to find the latest_revision for a page that didn't exist at a revision" do
    homepage = @wiki.pages.find("home")
    oid = homepage.latest_revision.oid
    head_oid = homepage.remove(@repo.owner)

    # we still have the cached page in memory and it'll lookup
    # it's own history based on the revision it was found at,
    # where it still existed
    assert_equal oid, homepage.latest_revision.oid

    # it's gone as of head_oid so this should return nil
    assert_nil homepage.latest_revision(head_oid)
  end

  test "normalizes newlines to unix for a new page" do
    name = "new-page"
    data = "new page\r\nwith windows line endings\r\n"
    page  = @wiki.pages.create name, :markdown, data, "initial #{name}", @repo.owner
    assert_equal "initial #{name}",   page.latest_revision.message
    assert_equal @repo.owner.login,   page.latest_revision.author_name
    assert_equal @repo.owner.email,   page.latest_revision.author_email
    assert_equal data.gsub(/\r/, ""), page.data
  end

  test "uses proper git data for commit" do
    page = @wiki.pages.find("edit-me")
    data = "more edits"
    @repo.owner.primary_user_email.toggle_visibility

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(commit_at = Time.zone.local(2014, 5, 15)) do
        page = page.update(page.name, data, page.format, "boom", @repo.owner)

        assert_equal "boom",                       page.latest_revision.message
        assert_equal @repo.owner.git_author_name,  page.latest_revision.author_name
        assert_equal @repo.owner.git_author_email, page.latest_revision.author_email
        assert_equal commit_at,                    page.latest_revision.authored_date
        assert_equal data,                         page.data
        assert_equal 36000, page.latest_revision.authored_date.utc_offset
      end
    end
  end

  test "normalizes newlines to unix on page update" do
    page = @wiki.pages.find("edit-me")
    data = "edited with\r\nwindows line endings\r\n"
    page = page.update(page.name, data, page.format, "boom", @repo.owner)

    assert_equal "boom",              page.latest_revision.message
    assert_equal @repo.owner.login,   page.latest_revision.author_name
    assert_equal @repo.owner.email,   page.latest_revision.author_email
    assert_equal data.gsub(/\r/, ""), page.data
  end

  test "doesn't normalize newlines to unix on page update if old file's line endings are the same as the new content" do
    page = @wiki.pages.find("windows")
    data = page.data + "with\r\n some more\r\ndata"
    page = page.update(page.name, data, page.format, "boom", @repo.owner)

    assert_equal "boom",              page.latest_revision.message
    assert_equal @repo.owner.login,   page.latest_revision.author_name
    assert_equal @repo.owner.email,   page.latest_revision.author_email
    assert_equal data,                page.data
  end

  test "doesn't normalize newlines to unix on page update even if not UTF-8" do
    page = @wiki.pages.find("windows-utf16")

    data = "edited with\r\nwindows line endings\r\n"
    page = page.update(page.name, data, page.format, "boom", @repo.owner)

    assert_equal "boom",              page.latest_revision.message
    assert_equal @repo.owner.login,   page.latest_revision.author_name
    assert_equal @repo.owner.email,   page.latest_revision.author_email
    assert_equal data, page.data
  end

  test "can rename a page title purely based by change in case" do
    page = @wiki.pages.find("edit-me")
    new_title = page.name.upcase
    page = page.update(new_title, page.data, page.format, "boom", @repo.owner)

    assert_equal "EDIT‐ME", page.name
  end
end
