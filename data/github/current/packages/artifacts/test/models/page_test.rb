# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/launch/dynamic_workflow_helper"
require "test_helpers/launch/identity_helper"

class PageTest < GitHub::TestCase
  include JobTestHelper
  include Launch::DynamicWorkflowHelper
  include Launch::IdentityHelper
  include HydroMessageJobTestHelpers

  # Helper method to test cname_from_blob without creating fixtures
  def normalized_cname(cname)
    Page.new.send(:normalize_cname, cname)
  end

  include PageHelper
  include HydroTestHelpers

  setup do
    Page::Certificate.stubs(:eligible?).returns(true)
    GitHub.flipper[:pages_github_app].disable
    GitHub.flipper[:diff_ux_refresh].disable

    # Stub the GH Pages and Launch apps
    pages_integration = create :github_pages_integration
    GitHub.stubs(:pages_github_app).returns(pages_integration)
    actions_integration = create :launch_integration
    GitHub.stubs(:launch_github_app).returns(actions_integration)
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  fixtures do
    @staff = create(:staff_admin_user)

    # A repo without a page yet.
    @repo = create(:repository)

    # An org affilliated with GitHub, serving pages under github.com
    @github_org = create(:organization, login: GitHub.github_owned_pages.first)

    # This is already created by machinist
    @github = Organization.find_by_login("github")

    @authorization_url = "http://boulder:4000/acme/authz/_fvjdv3Z9KaCjwzJ8BTHIS-IS_FAKEn2TmXQZlwJA7lU"
    @challenge_path = "/.well-known/acme-challenge/THIS-IS_FAKE-iAujkK1yvfXZyaNJhN3o--q1KBGdNdpXcey7cMF8"
    @challenge_response = "QC-THIS-IS_FAKE--q1KBGdNdpXcey7cMF8.uOEBl56QjcixTSwtE_yB-ouxAJPhUAl4US6neNtspXo"

    @alt_authorization_url = "http://boulder:4000/acme/authz/_THIS-IS_FAKEALTaAltkJ8BtnArwQVi7Mtn2TmALTuwJA7lU"
    @alt_challenge_path = "/.well-known/acme-challenge/QC-iAujkK1yTHIS-IS_FAKENJgB3d--w5KBGdNdpXcey7cNQ9"
    @alt_challenge_response = "QC-iAunmU1yvfXZyaNJhN3o--q1KBGwQfpXcey7cMF8.uOEBTHIS-IS_FAKE_yB-ouxAJPhUAl4US6neBnjiXo"
  end

  def make_user_page(user: nil, cname: nil, build_type: 0)
    args = { owner: user, cname: cname, build_type: build_type }.compact
    create :user_page, *(cname ? :with_cname_file : :built), **args
  end

  def make_project_page(repo: nil, user: nil, cname: nil, private: false)
    args = { repository: repo, owner: user, cname_file_content: cname, public: !private }.compact
    create :page, *(cname ? :with_cname_file : :built), **args
  end

  def make_cname_user_page(user: nil, cname: "user-page-cname.com", certificate: false)
    create :user_page, *(certificate ? :with_certificate : :with_cname_file), **{ owner: user, cname: cname }.compact
  end

  def make_cname_project_page(user: nil, cname: " ben.balter.com\nbenbalter.com")
    create :page, :with_cname_file, { owner: user, cname_file_content: cname }.compact
  end

  def make_dotcom_page
    create :built_page, owner: @github_org
  end

  def make_dotcom_cname_page
    create :built_page, :with_cname_file, owner: @github, cname: "somesite.github.com"
  end

  def make_docs_project_page(user: nil, cname: nil)
    args = { source: "master /docs", owner: user, cname: cname, docs_source: true }.compact
    create :page_on_master, *(cname ? :with_certificate : :built), **args
  end

  def make_master_project_page(user: nil, cname: nil)
    args = { owner: user, cname: cname }.compact
    create :page_on_master,  *(cname ? :with_cname_file : :built), **args
  end

  def make_arbitrary_branch_page
    create :built_page, owner: @github, source_ref_name: "arbitrary", source_subdir: "/"
  end

  test "github owned pages stay on github.com" do
    assert_equal GitHub.host_name, @github_org.pages_host_name
  end

  test "non-github owned pages use github.io" do
    if GitHub.enterprise?
      assert_equal GitHub.host_name, @staff.pages_host_name
    else
      assert_equal "github.io", @staff.pages_host_name
    end
  end

  test "works" do
    assert_difference "Page.count" do
      @repo.create_page
    end
  end

  context "#target_for_conditional_access" do
    test "returns repository owner" do
      page = @repo.create_page
      assert_equal @repo.owner, page.target_for_conditional_access
    end
  end

  context "#create_certificate" do
    test "creates a Page::Certificate" do
      GitHub.flipper[:pages_create_certificate_in_background].disable
      page = nil

      assert_difference("Page::Certificate.count", 1) do
        page = make_cname_user_page(user: @staff)
      end

      cert = Page::Certificate.last

      assert_equal(page.cname, cert.domain)
      assert_equal(:new, cert.current_state.to_sym)
    end

    test "does nothing if the feature is disabled" do
      GitHub.flipper[:pages_create_certificate_in_background].disable
      GitHub.stubs(:pages_custom_domain_https_enabled?).returns(false)

      assert_no_difference("Page::Certificate.count") do
        make_cname_user_page(user: @staff)
      end
    end

    test "does nothing if the certificate already exists" do
      GitHub.flipper[:pages_create_certificate_in_background].disable
      domain = "user-page-cname-two.com"
      Page::Certificate.create(domain: domain)

      assert_no_difference("Page::Certificate.count") do
        make_cname_user_page(user: @staff, cname: domain)
      end
    end

    test "does nothing if the CNAME is nil" do
      GitHub.flipper[:pages_create_certificate_in_background].disable
      assert_no_difference("Page::Certificate.count") do
        make_user_page(user: @staff)
      end
    end

  end if GitHub.acme_enabled?

  context "#create_certificate_in_background" do
    test "enqueues a background job to create the certificate" do
      GitHub.flipper[:pages_create_certificate_in_background].enable
      page = nil

      job = assert_enqueued_with(job: PageCertificateCreateJob) do
        page = make_cname_user_page(user: @staff)
      end
      assert_equal [page], job.arguments
    end
  end if GitHub.acme_enabled?

  test "sets correct visibility for imported private page" do
    @user = create(:user)
    @import = create(:import, creator: @user)
    @org  = create(:organization, admin: @user, plan: "free")
    @repo = create(:private_repository, owner: @org, import: @import)
    @repo.stubs(:is_importing?).returns(true)

    page = @repo.build_page public: false
    assert page
    refute page.public
  end

  test "sets correct visibility for imported public page" do
    @user = create(:user)
    @import = create(:import, creator: @user)
    @org  = create(:organization, admin: @user, plan: "free")
    @repo = create(:private_repository, owner: @org, import: @import)
    @repo.stubs(:is_importing?).returns(true)

    page = @repo.build_page public: true
    assert page
    assert page.public
  end

  test "sets correct visibility for forked public page of private repo" do
    GitHub.flipper[:pages_forked_visibility_fix].enable
    user = create(:user, plan: :free)
    org = create(:organization, plan: :business_plus, admin: user)
    org.allow_private_repository_forking(actor: user)
    org.allow_members_to_create_private_pages(actor: user)
    org.allow_members_to_create_public_pages(actor: user)

    repo = create(:private_repository, owner: org)
    assert repo.private?, "Expected repo.private? to be true"

    page = repo.create_page!
    page.update!(public: true)
    assert page.public?, "Expected page.public? to be true"

    forked_repo = create(:fork_repository, forker: user, fork_repo: repo)
    assert forked_repo, "Expected forked_repo to be present"
    assert forked_repo.private?, "Expected forked_repo.private? to be true"

    forked_page = forked_repo.create_page!

    assert forked_page.public?, "Expected forked_page.public? to be true"
  end

  context "#eligible_for_certificate?" do
    test "checks all the things" do
      page = make_user_page(user: @staff, cname: "lol.mastahyeti.com")
      assert page.eligible_for_certificate?
    end

    test "checks the dns" do
      Page::Certificate.stubs(:eligible?).returns(false)

      page = make_user_page(user: @staff, cname: "lol.mastahyeti.com")
      refute page.eligible_for_certificate?, "If DNS check fails, then false"
    end

    test "checks for presence of CNAME" do
      page = make_user_page(user: @staff)
      return page.eligible_for_certificate?, "If no cname, then false"
    end
  end if GitHub.acme_enabled?

  context "source directories and branches" do
    test "knows the dir and branch for user pages" do
      page = make_user_page
      assert_equal "main", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "", page.source_file_path
      assert_equal "", page.source_file_path("/")
      assert_equal "_config.yml", page.source_file_path("_config.yml")
      assert_equal 7, page.source_directory.items.length
      assert_match /hello world on main/, page.source_file("file-on-main")
      assert_nil page.source_file("file-on-gh-pages")
    end

    test "knows the dir and branch for project pages" do
      page = make_project_page
      assert_equal "gh-pages", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "", page.source_file_path
      assert_equal "", page.source_file_path("/")
      assert_equal "assets/css/style.css", page.source_file_path("/assets/css/style.css")
      assert_equal 8, page.source_directory.items.length
      assert_match /this file should only be on gh-pages/, page.source_file("file-on-gh-pages")
      assert_nil page.source_file("file-on-master")
    end

    test "knows the dir and branch for project pages with a master docs source" do
      page = make_docs_project_page
      assert_equal "master", page.source_branch
      assert_equal "/docs", page.source_dir
      assert_equal "docs", page.source_file_path
      assert_equal "docs", page.source_file_path("/")
      assert_equal "docs/index.md", page.source_file_path("/index.md")
      assert_equal 3, page.source_directory.items.length
      assert_equal "hello docs\n", page.source_file("index.html")
    end

    test "knows the dir and branch for project pages with a master source" do
      page = make_master_project_page
      assert_equal "master", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "", page.source_file_path
      assert_equal "", page.source_file_path("/")
      assert_equal "subdir1/subdir2/index.html", page.source_file_path("/subdir1/subdir2/index.html")
      assert_equal 6, page.source_directory.items.length
    end

    test "knows the dir and branch for pages with arbitrary branch and directory" do
      page = make_arbitrary_branch_page
      assert_equal "arbitrary", page.source_branch
      assert_equal "/", page.source_dir
      assert_equal "", page.source_file_path
      assert_equal "", page.source_file_path("/")
      assert_equal "assets/css/style.css", page.source_file_path("/assets/css/style.css")
      assert_equal 5, page.source_directory.items.length
      assert_match /this file should only be on arbitrary/, page.source_file("file-on-arbitrary")
      assert_nil page.source_file("file-on-gh-pages")
    end

    test "source is initialized in a backward compatible way when source_ref_name and source_subdir" do
      # Get any page (we don't care what it looks like)
      page = make_arbitrary_branch_page

      # master /
      page.set_source(ref_name: "master", subdir: "/")
      assert_equal "master", page.source

      # master /
      page.set_source(ref_name: "master", subdir: "/docs")
      assert_equal "master /docs", page.source

      # master /
      page.set_source(ref_name: "my-custom-branch", subdir: "/docs")
      assert_nil page.source

      # gh-pages
      page.set_source(ref_name: "gh-pages", subdir: "/")
      assert_nil page.source
    end
  end

  context "#subdir_source?" do
    test "false for legacy project pages" do
      refute_predicate make_project_page, :subdir_source?
    end

    test "true for project pages with a master /docs source" do
      assert_predicate make_docs_project_page, :subdir_source?
    end
  end

  context "#set_source" do
    test "allows valid source settings" do
      ["master /docs", "master"].each do |source|
        page = @repo.build_page source: source
        assert_equal page.source, source
        assert_valid page
      end
    end

    test "disallows invalid source setting" do
      page = @repo.build_page source: "master /doc" # should be "master /docs"
      assert_valid page
      assert_nil page.source
    end

    test "updates valid source setting on project pages" do
      page = make_project_page
      page.set_source(source: "master")
      assert_equal page.reload.source, "master"
    end

    test "accept source settings on user pages" do
      page = make_user_page
      page.set_source(ref_name: "master", subdir: "/docs")
      assert_equal "master /docs", page.reload.source
      assert_equal "master", page.source_ref_name
      assert_equal "/docs", page.source_subdir
    end
  end

  context "#cname_path" do
    test "CNAME files usually live in the root" do
      assert_equal "CNAME", create(:page, :with_cname_file).cname_path
    end

    test "CNAME files live in docs/ when source is master /doc" do
      assert_equal "docs/CNAME", make_docs_project_page.cname_path
    end
  end

  context "#set_cname" do
    if GitHub.pages_custom_cnames?
      test "rejects unauthorized github cname" do
        names = %w(github.com blog.github.com www.github.com)
        names.each do |name|
          page = @repo.build_page cname: name
          assert_valid page
          assert_nil page.cname
          assert_nil page.parent_domain
          assert_nil page.www_parent_domain
        end
      end

      test "disallows github.com cname" do
        name = "#{@repo.owner}.github.com"
        page = @repo.create_page cname: name
        assert_valid page
        assert_nil page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "disallows github.io cname" do
        name = "#{@repo.owner}.github.io"
        page = @repo.create_page cname: name
        assert_valid page
        assert_nil page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "allows homographic cname" do
        name = "exаmple.com" # The 'a' is a cyrillic character
        page = @repo.create_page cname: name
        assert_valid page
        assert_equal name, page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "pulls cname from blob for project pages" do
        page = make_cname_project_page
        assert_equal "ben.balter.com", page.cname
        assert_equal "balter.com", page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "extracts both parent_domain and www_parent_domain" do
        page = make_cname_project_page(cname: "www.subdomain.domain.co.uk")
        assert_equal "www.subdomain.domain.co.uk", page.cname
        assert_equal "subdomain.domain.co.uk", page.parent_domain
        assert_equal "domain.co.uk", page.www_parent_domain

        page = make_cname_project_page(cname: "www.domain.co.uk")
        assert_equal "www.domain.co.uk", page.cname
        assert_equal "domain.co.uk", page.parent_domain
        assert_nil page.www_parent_domain # .co.uk is a suffix
      end

      test "pulls cname from blob for user pages" do
        cname_page = make_cname_user_page
        assert_equal "user-page-cname.com", cname_page.cname
        assert_nil cname_page.parent_domain
        assert_nil cname_page.www_parent_domain
      end

      test "pulls CNAME from blob in /docs for docs pages" do
        page = make_docs_project_page(cname: "groovy.docs.com")
        assert_equal "groovy.docs.com", page.cname
        assert_equal "docs.com", page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "does not pull CNAME from blob in / for docs pages" do
        page = make_docs_project_page
        add_cname_file(page.repository, "ignore.this.com", "master", page.owner, "/")
        assert_nil page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
        assert_valid page
      end

      test "ignores CNAME in root when CNAME in docs pages docs folder" do
        page = make_docs_project_page(cname: "super.docs.com")
        add_cname_file(page.repository, "ignore.this.as.well.com", "master", page.owner, "/")
        assert_equal "super.docs.com", page.cname
        assert_equal "docs.com", page.parent_domain
        assert_nil page.www_parent_domain
        assert_valid page
      end

      test "ignores CNAME in docs when CNAME in master pages root" do
        page = make_master_project_page(cname: "awesomer.com")
        add_cname_file(page.repository, "boy-o-boy.com", "master", page.owner, "/docs")
        assert_equal "awesomer.com", page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
        assert_valid page
      end

      test "doesn't explode when a subdir is called CNAME" do
        repo = create(:repository)

        metadata = { message: "blah", committer: repo.owner }
        commit = repo.commits.create(metadata) do |files|
          files.add("CNAME/blah.txt", "sdfdsfds")
        end

        repo.heads.create("gh-pages", commit, repo.owner)

        page = repo.create_page
        assert_nil page.cname
        assert_nil page.parent_domain
        assert_nil page.www_parent_domain
      end

      test "doesn't explode when a subdir is called 404.html" do
        repo = create(:repository)

        metadata = { message: "blah", committer: repo.owner }
        commit = repo.commits.create(metadata) do |files|
          files.add("404.html/index.html", "sdfdsfds")
        end

        repo.heads.create("gh-pages", commit, repo.owner)

        page = repo.create_page
        refute page.four_oh_four
      end

      test "transcodes CNAME file to UTF-8 and strips byte order mark" do
        bom_cname_page = make_project_page(cname: "\xFF\xFEb\x00l\x00a\x00h\x00b\x00l\x00a\x00h\x00b\x00l\x00a\x00h\x00.\x00c\x00o\x00m\x00")
        assert_equal "blahblahblah.com", bom_cname_page.cname
        assert bom_cname_page.valid?
      end
    else
      test "doesn't allow cnames in Enterprise" do
        page = create(:page, :with_cname_file)
        page.save!
        assert_nil page.cname
      end
    end
  end

  context "#cname_error" do
    test "returns the CNAME error" do
      cname = "blog.github.com"
      page = @repo.create_page cname: cname
      expected = "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named #{@repo.owner}.#{@repo.owner.pages_host_name}. See #{GitHub.developer_help_url}/articles/setting-up-your-pages-site-repository/"
      assert_equal expected, page.cname_error(cname)
    end

    test "returns nil for valid CNAMEs" do
      cname = "mojombo.com"
      page = @repo.create_page cname: cname
      assert_nil page.cname_error(cname)
    end
  end if GitHub.pages_custom_cnames?

  test "user page can be rebuilt" do
    user_page = make_user_page
    assert user_page.repository.has_gh_pages?, "Expected #{user_page.repository.nwo} to have pages."
  end

  context "#normalize_cname" do
    test "normalizes multi-line cnames" do
      assert_equal "ben.balter.com", normalized_cname("ben.balter.com\nbenbalter.com")
    end

    test "normalizes multi-line cnames with whitespace" do
      assert_equal "ben.balter.com", normalized_cname(" ben.balter.com \n benbalter.com ")
    end

    test "normalizes empty cname files like a boss" do
      assert_nil normalized_cname("")
      assert_nil normalized_cname("\n")
      assert_nil normalized_cname(" ")
    end

    test "strips http:// from cnames" do
      assert_equal "github.com", normalized_cname("http://github.com")
    end

    test "strips https:// from cnames" do
      assert_equal "github.com", normalized_cname("https://github.com")
    end

    test "normalizes cname case" do
      assert_equal "github.com", normalized_cname("GitHub.com")
    end

    test "strips whitespace from cnames" do
      assert_equal "github.com", normalized_cname(" github.com ")
    end

    test "normalizes cnames that make absolutely no sense" do
      assert_nil normalized_cname(" HTTP:// \n ")
    end

    test "punycodes cnames which contain non-ascii characters" do
      GitHub.flipper[:pages_punycode_cert_names].enable
      assert_equal "xn--rsum-bpad.pages.qingy.icu", normalized_cname("résumé.pages.qingy.icu")
    end

    test "does not change punycoded cnames" do
      GitHub.flipper[:pages_punycode_cert_names].enable
      assert_equal "xn--rsum-bpad.pages.qingy.icu", normalized_cname("xn--rsum-bpad.pages.qingy.icu")
    end
  end if GitHub.pages_custom_cnames?

  context "#write_cname" do
    test "commits valid CNAMEs and rebuilds pages" do
      GitHub.flipper[:pages_github_app].disable
      user_page = make_user_page
      ["my.domain.yay", "happy.me"].each do |cname|
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob, HydroRepositoriesOnPushJob]) do
          perform_enqueued_jobs(only: [PageBuildJob]) do
            assert_equal cname, user_page.write_cname(cname, user_page.owner)
          end
        end

        assert_equal cname, user_page.reload.cname
        # 1 rebuild only (we skip the explicit one we used to trigger) and just go with a post-receive one
        assert_equal 1, GitHub.dogstats.increments("pages.build_jobs").count
      end
    end

    test "rejects invalid cnames" do
      user_page = make_user_page
      ["　 github.com ", "10.0.0.1", "bogus", "GITHUB.COM", "+-=_+_+", "$"].each do |cname|
        assert_raises(Page::InvalidCNAME) do
          user_page.write_cname(cname, user_page.owner)
        end
      end
    end

    test "rejects DNS style entries" do
      user_page = make_user_page
      ["example.com. alias example.github.io", "example.comalias example.github.io"].each do |cname|
        assert_raises(Page::InvalidCNAME) do
          user_page.write_cname(cname, user_page.owner)
        end
      end
    end

    test "commits blank CNAMEs and rebuilds pages" do
      GitHub.flipper[:pages_github_app].disable
      user_page = make_cname_user_page
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob, HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [PageBuildJob]) do
          assert_equal "", user_page.write_cname("", user_page.owner)
        end
      end

      assert_nil user_page.reload.cname
      # 1 rebuild only (we skip the explicit one we used to trigger) and just go with a post-receive one
      assert_equal 1, GitHub.dogstats.increments("pages.build_jobs").count
    end

    test "commits with commit messages" do
      user_page = make_user_page
      cname = "www.example.com"
      cname2 = "ilikes.swedishfish.com"
      refute user_page.cname_exists?
      assert_equal cname, user_page.write_cname(cname, user_page.owner)
      assert_equal user_page.pages_ref.commit.message, "Create CNAME"
      assert_equal cname2, user_page.write_cname(cname2, user_page.owner)
      assert_equal user_page.pages_ref.commit.message, "Update CNAME"
      assert_equal "", user_page.write_cname("", user_page.owner)
      assert_equal user_page.pages_ref.commit.message, "Delete CNAME"
    end

    test "commits CNAME to /docs" do
      cname = "docs.in-the-docs-folder.com"
      page = make_docs_project_page
      perform_enqueued_jobs(only: PageBuildJob) do
        assert_equal cname, page.write_cname(cname, page.owner)
      end
      assert_equal cname, page.reload.cname
    end

    test "not commit CNAME when build type is workflow" do
      user_page = make_user_page(build_type: "workflow")

      cname = "www.example.com"
      refute user_page.cname_exists?

      assert_equal cname, user_page.write_cname(cname, user_page.owner)

      # no new commit made
      assert_nil user_page.pages_ref&.commit&.message

      assert_equal "", user_page.write_cname("", user_page.owner)

      # no new commit made
      assert_nil user_page.pages_ref&.commit&.message
    end

    test "commit cname file does not add cname when build type is workflow" do
      page = make_docs_project_page
      page.build_type = "workflow"

      # with the workflow build type, source_branch is nil, but even with the legacy type, even it's there before, it should still pass the test case.
      add_cname_file(page.repository, "groovy.docs.com", page.source_branch, page.owner, "/") if page.source_branch.present?

      assert_valid page
      assert_nil page.cname
    end

    test "does not add cname when page is soft-deleted", skip_enterprise: true do
      GitHub.flipper[:pages_soft_deletion].enable
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      page = create :private_page
      page.soft_delete!

      assert_nil page.write_cname("my.domain.yay", page.owner)
      assert_nil page.reload.cname
    end
  end if GitHub.pages_custom_cnames?

  context "subdomain with owner changes in proxima" do
    test "updates the page's subdomain in proxima for an emu" do
      on_multi_tenant_enterprise

      page = create(:emu_owned_proxima_page, :built)
      user = page.owner

      original_subdomain = page.subdomain

      refute_nil page
      user.rename!("renamed_#{user.enterprise_managed_business.shortcode}")
      new_subdomain = page.reload.subdomain
      refute_equal original_subdomain, new_subdomain
      assert_equal new_subdomain, "#{user.display_login}-#{page.repository.name}_#{user.enterprise_managed_business.shortcode}"
    end

    test "updates the page's subdomain in proxima for an org" do
      on_multi_tenant_enterprise

      page = create(:org_owned_proxima_page)
      original_subdomain = page.subdomain
      refute_nil page
      repo = page.repository
      owner = page.owner
      repo.owner.rename!("i-am-foo")
      new_subdomain = page.reload.subdomain
      refute_equal original_subdomain, new_subdomain
      assert_equal new_subdomain, "#{owner.display_login}-#{repo.name}_#{owner.business.shortcode}"
    end

    test "update the pages subdomain when repository ownership is transferred in proxima" do
      on_multi_tenant_enterprise

      page = create(:org_owned_proxima_page)
      user = page.owner.admin

      original_subdomain = page.subdomain
      refute_nil page
      repo = page.repository
      new_org = create(:organization)
      new_org.add_member(user, action: :admin)
      repo.transfer_ownership_to(new_org, actor: user)

      new_subdomain = page.reload.subdomain
      refute_equal original_subdomain, new_subdomain
      assert_equal new_subdomain, "#{new_org.display_login}-#{repo.name}_#{new_org.business.shortcode}"
    end
  end

  context "repo rename" do
    test "updates the page's subdomain in proxima" do
      on_multi_tenant_enterprise

      page = create(:org_owned_proxima_page)

      original_subdomain = page.subdomain
      refute_nil page
      page.repository.rename("proxima-site", actor: page.owner.admin)
      refute_equal original_subdomain, page.subdomain
    end

    test "maintains page when a user page repo is renamed to a project page repo" do
      repo = make_user_page.repository
      refute_nil repo.page
      repo.rename "project-site"
      refute_nil repo.reload.page
    end

    test "maintains page when a project page repo is renamed to a user page repo" do
      repo = make_project_page.repository
      refute_nil repo.page
      repo.rename "#{repo.owner}.#{repo.owner.pages_host_name}"
      refute_nil repo.reload.page
    end

    test "retains page when a project repo is renamed to another project repo" do
      repo = make_project_page.repository
      refute_nil repo.page
      repo.rename "project-site"
      refute_nil repo.reload.page
    end

    test "maintains branch and CNAME when project repo is renamed to user repo" do
      # Project page with different CNAME in master branch
      dual_cname_project_page = create :page, :with_cname_file, cname: "project1.co.uk"
      add_cname_file(dual_cname_project_page.repository, "user1.co.uk", "master")

      repo = dual_cname_project_page.repository
      assert_equal "project1.co.uk", repo.page.cname
      assert_equal "gh-pages", repo.page.source_ref_name
      assert_equal "/", repo.page.source_subdir
      repo.rename "#{repo.owner}.#{repo.owner.pages_host_name}"
      assert_equal "project1.co.uk", dual_cname_project_page.reload.cname
      assert_equal "gh-pages", dual_cname_project_page.source_ref_name
      assert_equal "/", dual_cname_project_page.source_subdir
    end if GitHub.pages_custom_cnames?

    test "maintains source and CNAME when user repo is renamed to project repo" do
      # User page with different CNAME in gh-pages branch
      dual_cname_user_page = create :user_page, :with_cname_file, cname: "user2.co.uk"
      add_cname_file(dual_cname_user_page.repository, "project2.co.uk", "gh-pages")
      repo = dual_cname_user_page.repository.reload
      # cname is needed to get cname to update.
      repo.page.save
      assert_equal "main", repo.page.source_ref_name
      assert_equal "/", repo.page.source_subdir

      assert_equal "user2.co.uk", repo.page.cname
      repo.rename "this-is-now-a-project-repo"
      assert_equal "user2.co.uk", repo.reload.page.cname
      assert_equal "main", repo.page.source_ref_name
      assert_equal "/", repo.page.source_subdir
    end if GitHub.pages_custom_cnames?
  end

  context "#https_available?" do
    test "true for github.io pages" do
      if GitHub.pages_https_redirect_enabled?
        assert_predicate create(:built_page), :https_available?
      else
        refute_predicate create(:built_page), :https_available?
      end
    end

    test "true for github.com pages" do
      if GitHub.pages_https_redirect_enabled?
        assert_predicate make_dotcom_page, :https_available?
      else
        refute_predicate make_dotcom_page, :https_available?
      end
    end

    test "true for github.com CNAME pages" do
      if GitHub.pages_https_redirect_enabled?
        assert_predicate make_dotcom_cname_page, :https_available?
      else
        refute_predicate make_dotcom_cname_page, :https_available?
      end
    end

    test "false for project pages with CNAME" do
      refute_predicate make_cname_project_page, :https_available?
    end

    test "false for user pages with CNAME" do
      refute_predicate make_cname_user_page, :https_available?
    end

    test "false for project-pages inheriting a CNAME from the user-page" do
      user_page = make_cname_user_page
      refute_predicate make_project_page(user: user_page.owner), :https_available?
    end

    test "true for whitelisted domains on dotcom" do
      cname_page = create(:page, :with_cname_file, cname: "svnhub.com")
      if GitHub.enterprise?
        refute_predicate cname_page, :https_available?
      else
        assert_predicate cname_page, :https_available?
      end
    end

    test "true for pages with a Page::Certificate" do
      page = make_cname_user_page(certificate: true)
      page.certificate.update(
        state: :approved,
        expires_at: 90.days.from_now,
      )
      page.reload

      refute_nil page.certificate
      assert_predicate page, :https_available?
    end if GitHub.acme_enabled?
  end

  context "#https_redirect_required?" do
    test "true for github.com pages" do
      if GitHub.pages_https_redirect_enabled?
        assert_predicate make_dotcom_page, :https_redirect_required?
      else
        refute_predicate make_dotcom_page, :https_redirect_required?
      end
    end

    test "true for github.com CNAME pages" do
      if GitHub.pages_https_redirect_enabled?
        assert_predicate make_dotcom_cname_page, :https_redirect_required?
      else
        refute_predicate make_dotcom_cname_page, :https_redirect_required?
      end
    end

    test "false for old github.io pages" do
      refute_predicate create(:page, :repo_before_https), :https_redirect_required?
    end

    test "true for new github.io pages" do
      new_page = create(:page, :repo_after_https)
      if GitHub.pages_https_redirect_enabled?
        assert_predicate new_page, :https_redirect_required?
      else
        refute_predicate new_page, :https_redirect_required?
      end
    end

    test "false for old project pages with CNAME" do
      refute_predicate create(:page, :repo_before_https, cname: "project.old"), :https_redirect_required?
    end

    test "false for new project pages with CNAME" do
      refute_predicate create(:page, :repo_after_https, cname: "project.new"), :https_redirect_required?
    end

    test "false for master-source project pages with CNAME" do
      page = create(:page_on_master, :with_cname_file, cname: "master-project.co.za")
      refute_predicate page, :https_redirect_required?
    end

    test "false for old user pages with CNAME" do
      refute_predicate create(:user_page, :repo_before_https, :with_cname_file, cname: "user.old"), :https_redirect_required?
    end

    test "false for new user pages with CNAME" do
      refute_predicate create(:user_page, :repo_after_https, :with_cname_file, cname: "user.new"), :https_redirect_required?
    end

    test "false for old project-pages inheriting a CNAME from the user-page" do
      user_page = create(:user_page, cname: "foo.com")
      refute_predicate create(:page, :repo_before_https, owner: user_page.owner), :https_redirect_required?
    end

    test "false for new project-pages inheriting a CNAME from the user-page" do
      user_page = create(:user_page, cname: "foo.com")
      refute_predicate create(:page, :repo_after_https, owner: user_page.owner), :https_redirect_required?
    end

    test "false for custom domains with a certificate" do
      page = create :page, :with_certificate, cname: "www.mikeperham.com"

      if GitHub.pages_https_redirect_enabled?
        assert_predicate page, :https_available?
        refute_predicate page, :https_redirect_required?
      elsif GitHub.pages_custom_domain_https_enabled?
        assert_predicate page, :https_available?
        refute_predicate page, :https_redirect_required?
      else
        refute_predicate page, :https_available?
        refute_predicate page, :https_redirect_required?
      end
    end
  end

  context "#subdomain" do
    test "doesn't create a subdomain on primary pages" do
      page = make_user_page
      owner = page.repository.owner
      owner.update(plan: GitHub::Plan::BUSINESS_PLUS)
      page.update_attribute(:public, false)

      assert_nil page.subdomain
    end

    test "primary pages do not exist in Proxima" do
      on_multi_tenant_enterprise

      user = create :emu, login: "mtemu"
      business = user.enterprise_managed_business
      org = create :organization, business: business, admin: user

      primary_org_name = "#{org.to_s.downcase}.#{GitHub.pages_host_name_v2}".downcase
      org_repo = create(:repository, owner: org, name: primary_org_name)
      org_page = create(:page, repository: org_repo)

      primary_emu_name = "#{user.to_s.downcase}.#{GitHub.pages_host_name_v2}".downcase
      emu_repo = create(:repository, owner: user, force_user_owned: true, name: primary_emu_name)
      emu_page = create(:page, repository: emu_repo)

      refute org_page.primary?
      refute emu_page.primary?
    end

    test "not creates certificate when subdomain is set", skip_enterprise: true do
      GitHub.stubs(:pages_custom_domain_https_enabled?).returns(true)
      repo = create :repository, name: "Wow_Repo"
      repo.owner.update(plan: GitHub::Plan::BUSINESS_PLUS)
      page = make_project_page(repo: repo, private: true)
      refute Page::Certificate.all.include?(page.url.host)
    end

    test "set pages subdomain when visibility set to private" do
      repo = create :repository, name: "Test_Repo"
      repo.owner.update(plan: GitHub::Plan::BUSINESS_PLUS)

      page = make_project_page(repo: repo, private: true)

      refute_nil page.subdomain
    end

    test "reset subdomain when page is public" do
      repo = create :repository, name: "Test_Repo"
      repo.owner.update(plan: GitHub::Plan::BUSINESS_PLUS)
      page = make_project_page(repo: repo, private: true)

      refute_nil page.subdomain

      page.update_attribute :public, true

      assert_nil page.subdomain
    end

    test "hostname for primary repository should be the same as the repo name", skip_enterprise: true do
      page = make_user_page

      assert_equal page.repository.name, page.url.host
    end

    test "does not rename subdomain for page build" do
      page = make_user_page
      original_subdomain = "foo"
      page.subdomain = original_subdomain
      page.save!
      page.repository.rebuild_pages
      page.reload

      assert_equal page.subdomain, original_subdomain
    end
  end

  context "hsts_required?" do
    test "for new users' sites without CNAME" do
      user_page = create(:page, :primary, :repo_after_https, :owner_after_https)
      if GitHub.pages_https_redirect_enabled?
        assert_predicate user_page, :hsts_required?
      else
        refute_predicate user_page, :hsts_required?
      end
    end

    test "for old users' sites without CNAME" do
      user_page = create(:user_page, :owner_before_https, :repo_before_https)
      refute_predicate user_page, :hsts_required?
    end

    test "for new users' sites with CNAME" do
      user_page = create(:page, :owner_after_https, :repo_after_https, cname: "new.user.cname.site")
      refute_predicate user_page, :hsts_required?
    end

    test "for old users' sites with CNAME" do
      user_page = create(:page, :owner_before_https, :repo_after_https, cname: "old.user.cname.site")
      refute_predicate user_page, :hsts_required?
    end

    test "for httpsable GitHub-owned sites" do
      project_page = create :page, owner: @github, cname: "choosealicense.com"
      if GitHub.pages_https_redirect_enabled?
        assert_predicate project_page, :https_available?
        assert_predicate project_page, :hsts_required?
      else
        refute_predicate project_page, :https_available?
        refute_predicate project_page, :hsts_required?
      end
    end
  end

  context "#https_redirect_toggleable?" do
    test "false for github.com pages" do
      refute_predicate make_dotcom_page, :https_redirect_toggleable?
    end

    test "false for github.com CNAME pages" do
      refute_predicate make_dotcom_cname_page, :https_redirect_toggleable?
    end

    test "true for old github.io pages" do
      page = create :page_before_https
      if GitHub.pages_https_redirect_enabled?
        assert_predicate page, :https_redirect_toggleable?
      else
        refute_predicate page, :https_redirect_toggleable?
      end
    end

    test "false for project pages with CNAME" do
      refute_predicate make_cname_project_page, :https_redirect_toggleable?
    end

    test "false for user pages with CNAME" do
      refute_predicate make_cname_user_page, :https_redirect_toggleable?
    end

    test "false for project-pages inheriting a CNAME from the user-page" do
      user_page = make_cname_user_page
      refute_predicate make_project_page(user: user_page.owner), :https_redirect_toggleable?
    end
  end

  context "set_https_redirect" do
    test "removes project-page https_redirect when user-page gets CNAME" do
      user_page = make_user_page
      project_page = make_project_page(user: user_page.owner)

      assert_predicate project_page.reload, :https_redirect?
      assert_predicate project_page, :https_redirect_required?

      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob, HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
          add_cname_file(user_page.repository, "page.com", "main")
        end
      end

      refute_predicate project_page.reload, :https_redirect?
      refute_predicate project_page, :https_redirect_required?
    end

    test "adds project-page https_redirect when user-page loses CNAME" do
      cname_user_page = make_cname_user_page
      effective_cname_project_page = make_project_page(user: cname_user_page.owner)

      refute_predicate effective_cname_project_page.reload, :https_redirect?
      refute_predicate effective_cname_project_page, :https_redirect_required?

      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob, HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
          remove_cname(cname_user_page.repository, cname_user_page.source_ref_name)
        end
      end

      assert_predicate effective_cname_project_page.reload, :https_redirect?
      assert_predicate effective_cname_project_page, :https_redirect_required?
    end

    test "adds project-page https_redirect when CNAME user-page is destroyed" do
      cname_user_page = make_cname_user_page
      effective_cname_project_page = make_project_page(user: cname_user_page.owner)

      refute_predicate effective_cname_project_page.reload, :https_redirect?
      refute_predicate effective_cname_project_page, :https_redirect_required?

      perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
        cname_user_page.repository.destroy
      end

      assert_predicate effective_cname_project_page.reload, :https_redirect?
      assert_predicate effective_cname_project_page, :https_redirect_required?
    end

    test "adds project-page https_redirect when CNAME user-page repo is renamed" do
      cname_user_page = make_cname_user_page
      effective_cname_project_page = make_project_page(user: cname_user_page.owner)

      refute_predicate effective_cname_project_page.reload, :https_redirect?
      refute_predicate effective_cname_project_page, :https_redirect_required?

      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob]) do
        perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
          cname_user_page.repository.rename(SecureRandom.hex)
        end
      end

      assert_predicate effective_cname_project_page.reload, :https_redirect?
      assert_predicate effective_cname_project_page, :https_redirect_required?
    end

    test "removes project-page https_redirect when CNAME user-page is created" do
      standalone_project_page = make_project_page
      assert_predicate standalone_project_page.reload, :https_redirect?
      assert_predicate standalone_project_page, :https_redirect_required?
      user_page = create :user_page, :built, owner: standalone_project_page.owner

      perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroPagesOnPushJob, HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
          add_cname_file(user_page.repository, "somedomainforuserpage.com", user_page.source_ref_name)
        end
      end

      refute_predicate standalone_project_page.reload, :https_redirect?
      refute_predicate standalone_project_page, :https_redirect_required?
    end

    test "removes project-page https_redirect when CNAME project-page is renamed to CNAME user-page" do
      dual_branch_project_page = create :page, :with_cname_file, cname: "irrelevant.com"
      repo = dual_branch_project_page.repository
      add_cname_file(repo, "brexit.aint-happening.co.uk", "master")

      standalone_project_page = make_project_page(user: repo.owner)
      assert_predicate standalone_project_page.reload, :https_redirect?
      assert_predicate standalone_project_page, :https_redirect_required?

      perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
        repo.rename "#{repo.owner}.#{repo.owner.pages_host_name}"
      end

      refute_predicate standalone_project_page.reload, :https_redirect?
      refute_predicate standalone_project_page, :https_redirect_required?
    end

    test "!removes project-page https_redirect when non-CNAME project-page is renamed to CNAME user-page" do
      dual_branch_project_page = create :page_with_heads
      assert_equal "gh-pages", dual_branch_project_page.source_ref_name
      assert_equal "/", dual_branch_project_page.source_subdir
      repo = dual_branch_project_page.repository
      add_cname_file(repo, "brexit.aint-happening.co.uk", "master")

      standalone_project_page = make_project_page(user: repo.owner)
      assert_predicate standalone_project_page.reload, :https_redirect?
      assert_predicate standalone_project_page, :https_available?
      assert_predicate standalone_project_page, :https_redirect_required?

      perform_enqueued_jobs(only: [PagesPropagateHttpsRedirectJob]) do
        repo.rename "#{repo.owner}.#{repo.owner.pages_host_name}"
      end

      assert_equal "gh-pages", dual_branch_project_page.source_ref_name
      assert_equal "/", dual_branch_project_page.source_subdir
      assert_predicate standalone_project_page.reload, :https_redirect?
      assert_predicate standalone_project_page, :https_available?
      assert_predicate standalone_project_page, :https_redirect_required?
    end

    test "removes https_redirect when master-docs project-page acquires a CNAME" do
      docs_project_page = make_docs_project_page
      assert_predicate docs_project_page, :https_redirect?
      add_cname_file(docs_project_page.repository, "project-docs.io", "master", nil, "/docs")
      docs_project_page.reload
      assert_valid docs_project_page
      assert_equal "project-docs.io", docs_project_page.cname
      refute_predicate docs_project_page, :https_redirect?
    end

    test "adds https_redirect when master project-page with a CNAME becomes docs project-page without a CNAME" do
      master_project_page = make_master_project_page(cname: "master-project.cn")
      assert_equal "master-project.cn", master_project_page.cname
      refute_predicate master_project_page, :https_redirect?
      master_project_page.set_source(ref_name: "master", subdir: "/docs")
      assert_valid master_project_page
      assert_equal "master /docs", master_project_page.source
      assert_equal "master", master_project_page.source_ref_name
      assert_equal "/docs", master_project_page.source_subdir
      assert_nil master_project_page.cname
      assert_predicate master_project_page, :https_redirect?
    end
  end if GitHub.pages_https_redirect_enabled?

  context "create_or_find_deployment_for" do
    test "automatically creates the deployment if it doesn't exist" do
      page = make_project_page
      assert_equal 0, page.deployments.size

      deployment = page.create_or_find_deployment_for(page.source_branch)
      page.reload

      assert_equal 1, page.deployments.size
    end

    test "finds the deployment based on ref_name if it does exist" do
      page = make_project_page
      first = page.create_or_find_deployment_for("a-branch")
      second = page.create_or_find_deployment_for("a-branch")
      page.reload

      assert_equal 1, page.deployments.size
      assert_equal first.id, second.id, "Deployment IDs should be the same."
      assert_equal first.token, second.token, "Deployment tokens should be the same."
    end

    test "updates the token if it clashes" do
      page = make_project_page
      # First time, the token is used to create the first deployment.
      # Second time, the token is used to create the second deployment. There is a clash, so:
      # Third time, a new token is used to create the second deployment.
      Page::Deployment.expects(:generate_token).times(3).returns("atokenforyou", "atokenforyou", "anothertoken")
      first = page.create_or_find_deployment_for("another-branch")
      second = page.create_or_find_deployment_for("yet-another-branch")
      page.reload

      assert_equal 2, page.deployments.size
      refute_equal first.id, second.id
      refute_equal first.token, second.token
    end
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end

  context "static only deployment" do
    test "if nojekyll file does not exist in a legacy Page" do
      GitHub.flipper[:pages_static_only_deployment].enable
      Page.any_instance.stubs(:dynamic_workflow_disabled_reason).returns("some value")
      Page.any_instance.stubs(:nojekyll?).returns(false)

      page = make_project_page
      page.publish(page.repository.owner)

      GitHub::Pages::PagesDeployerClient.expects(:enqueue).never
    end

    test "if nojekyll file exists in a legacy Page", skip_enterprise: true do
      GitHub.flipper[:pages_static_only_deployment].enable
      Page.any_instance.stubs(:dynamic_workflow_disabled_reason).returns("some value")
      Page.any_instance.stubs(:nojekyll?).returns(true)
      GitHub::Pages::Replicator.any_instance.stubs(:hosts_with_datacenter).returns([{ name: "localhost", non_voting: false, datacenter: nil }])
      page = make_project_page

      page.create_or_find_deployment_for(page.source_branch)
      sha1 = page.repository.refs.find(page.source_branch).commit.oid
      gh_deployment = ::Deployment.create(repository: page.repository, repository_id: page.repository.id, creator: GitHub.pages_github_app.bot, sha: sha1)
      built_version = page.repository.heads.find(page.source_branch)&.target.oid
      url = "#{GitHub.api_url}/repos/#{page.repository.name_with_owner_for_api}/tarball/#{page.source_branch}"
      queue_name = "pages-deployer"
      expected_payload = generate_deployment_payload(page, built_version: built_version, url: url)
      expected_payload.delete(:hosts)
      expected_payload.delete(:preview_token)

      additional_payload = {
        deployment_type: 1,
        sub_dir: "/",
        nwo: page.repository.name_with_owner,
        github_deployment_id: gh_deployment.id,
      }

      expected_payload = expected_payload.merge(additional_payload)

      GitHub::Pages::PagesDeployerClient.expects(:enqueue).once.with(expected_payload, queue_name)
      page.publish(page.repository.owner)

    end
  end

  context "instrumentation" do
    test "pages_create" do
      cname = "www.example.co.za"
      events = subscribe "repo.pages_create"
      repo = create(:page, :with_cname_file, cname: cname).repository
      assert event = events.pop, "expected an event"
      assert_equal repo.nwo, event.payload[:repo]
      assert_equal cname, event.payload[:cname] if GitHub.pages_custom_cnames?
    end

    test "pages_create with source" do
      create_events = subscribe "repo.pages_create"
      source_events = subscribe "repo.pages_source"
      repo = create(:page_on_master).repository
      assert event = create_events.pop, "expected an event"
      assert_equal repo.nwo, event.payload[:repo]
      assert event = source_events.pop, "expected an event"
      assert_equal "master /", event.payload[:source]
    end

    test "pages_create with source_ref_name 'main'" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create_events = subscribe "repo.pages_create"
      source_events = subscribe "repo.pages_source"
      page = create(:page, example_repo: :pages_main_only, source_ref_name: "main", source_subdir: "/")
      repo = page.repository

      assert event = create_events.pop, "expected an event"
      assert_equal repo.nwo, event.payload[:repo]
      assert event = source_events.pop, "expected an event"
      assert_equal "main /", event.payload[:source]
      assert_nil event.payload[:old_source]
      assert_equal 1, GitHub.dogstats.increments("pages.source", tags: ["branch:main", "dir:/"]).count
    end

    test "pages update source_subdir '/docs'" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      source_events = subscribe "repo.pages_source"
      page = create(:page, example_repo: :pages_main_only, source_ref_name: "main", source_subdir: "/")
      page.update!(source_subdir: "/docs")

      assert_equal 2, source_events.length
      assert event = source_events.last, "expected an event"
      assert_equal "main /docs", event.payload[:source]
      assert_equal "main /", event.payload[:old_source]
      assert_equal 1, GitHub.dogstats.increments("pages.source", tags: ["branch:main", "dir:/docs"]).count
    end

    test "pages update source_ref_name 'custom'" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      source_events = subscribe "repo.pages_source"
      page = create :page, source_ref_name: "main", source_subdir: "/", example_repo: :pages_main_only
      page.update!(source_ref_name: "custom")

      assert_equal 2, source_events.length
      assert event = source_events.last, "expected an event"
      assert_equal "custom /", event.payload[:source]
      assert_equal "main /", event.payload[:old_source]
      assert_equal 1, GitHub.dogstats.increments("pages.source", tags: ["branch:other", "dir:/"]).count
    end

    test "pages update source_ref_name from deprecated source" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      source_events = subscribe "repo.pages_source"
      page = create(:page_on_master, docs_source: true)
      page.update_columns(source_ref_name: nil, source_subdir: nil)
      page.update!(source_ref_name: "master")

      assert_equal 2, source_events.length
      assert event = source_events.last, "expected an event"
      assert_equal "master /docs", event.payload[:source]
      assert_equal "master /docs", event.payload[:old_source]
      assert_equal 2, GitHub.dogstats.increments("pages.source", tags: ["branch:master", "dir:/docs"]).count
    end

    test "pages update build_type" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      events = subscribe "repo.pages_build_type"
      page = create(:page, example_repo: :pages_main_only)
      page.update!(build_type: "workflow")

      assert_equal 2, events.length
      before, after = events
      assert_equal "legacy", before.payload[:build_type]
      assert_equal "workflow", after.payload[:build_type]
    end

    test "!pages_destroy" do
      cname = "www.example.cn"
      events = subscribe "repo.pages_destroy"
      repo = create(:user_page, :with_cname_file, cname: cname).repository
      repo.rename("project-name")
      assert_nil events.pop
      page = repo.page.reload
      assert_nil page.source # this is a legal value (nil = master for primary repo)
      assert_equal "main", page.source_ref_name
      assert_equal "/", page.source_subdir
    end

    test "pages_replicas & page_deployments are destroyed upon Page destruction" do
      unrelated_page = make_project_page
      deploy_page(unrelated_page)
      page = make_project_page
      deploy_page(page)

      assert_equal 1, Page::Deployment.where(page_id: page.id).count
      assert_equal 1, Page::Replica.where(page_id: page.id).count

      page.destroy

      assert_equal 0, Page::Deployment.where(page_id: page.id).count
      assert_equal 0, Page::Replica.where(page_id: page.id).count

      # Don't mess with other pages.
      assert_equal 1, Page::Deployment.where(page_id: unrelated_page.id).count
      assert_equal 1, Page::Replica.where(page_id: unrelated_page.id).count
    end

    test "cname" do
      user_page = make_user_page
      cname = "www.example.co.uk"
      events = subscribe "repo.pages_cname"

      perform_enqueued_jobs(only: PageBuildJob) do
        user_page.write_cname(cname, user_page.owner)
      end

      assert event = events.pop, "expected an event"
      assert_equal cname, event.payload[:cname]

      perform_enqueued_jobs(only: PageBuildJob) do
        user_page.write_cname("", user_page.owner)
      end

      assert event = events.pop, "expected an event"
      assert_equal cname, event.payload[:old_cname]
      assert_nil event.payload[:cname]
    end if GitHub.pages_custom_cnames?

    test "https_redirect toggle" do
      user_page = create :page_before_https, :primary
      user_page.update(https_redirect: false)
      events = subscribe "repo.pages_https_redirect_enabled"
      user_page.update(https_redirect: true)
      assert event = events.pop, "expected an event"
      assert_equal user_page.repository.nwo, event.payload[:repo]
    end if GitHub.pages_https_redirect_enabled?

    test "hydro cname changed" do
      GitHub.stubs(:hydro_enabled?).returns(true)

      user_page = make_user_page
      old_cname = "www.example.co.uk"

      PageBuildJob.perform_now(user_page.write_cname(old_cname, user_page.owner), nil)

      new_cname = "www.example.com"
      PageBuildJob.perform_now(user_page.write_cname(new_cname, user_page.owner), nil)

      message = {
        page: Hydro::EntitySerializer.page(user_page),
        actor: Hydro::EntitySerializer.user(user_page.owner),
        cname: new_cname,
        old_cname: old_cname,
      }
      assert_hydro_published(message, schema: "github.v1.RepositoryPagesCnameChange")
    end if GitHub.pages_custom_cnames?

    test "hydro pages build" do
      # Not supporting dynamic workflows
      GitHub.stubs(:actions_enabled?).returns(false)
      GitHub.stubs(:hydro_enabled?).returns(true)

      user = create(:user)
      user_page = create :user_page, repository: @repo
      user_page.publish(user)

      message = {
        page: Hydro::EntitySerializer.page(user_page),
        actor: Hydro::EntitySerializer.user(user),
        repository_owner: Hydro::EntitySerializer.user(user_page.repository.owner),
      }
      assert_hydro_published(message, schema: "github.v1.RepositoryPagesBuild")
    end

    test "emits a metric when a public page is created" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user, plan: GitHub::Plan::BUSINESS_PLUS)

      repo = create(:repository, owner: user)
      create(:page, repository: repo, public: true)

      assert_equal 1, GitHub.dogstats.increments("pages.visibility", tags: ["action:public"]).count
      assert_equal 0, GitHub.dogstats.increments("pages.visibility", tags: ["action:private"]).count
    end

    test "emits a metric when a public page is updated to private" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user, plan: GitHub::Plan::BUSINESS_PLUS)

      repo = create(:repository, owner: user)
      page = create(:page, repository: repo, public: true)
      page.update!(public: false)

      assert_equal 1, GitHub.dogstats.increments("pages.visibility", tags: ["action:public"]).count
      assert_equal 1, GitHub.dogstats.increments("pages.visibility", tags: ["action:private"]).count
    end

    test "does not emit a metric when a public page's visibility does not change" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user, plan: GitHub::Plan::BUSINESS_PLUS)

      repo = create(:repository, owner: user)
      page = create(:page, repository: repo, public: true)
      page.update!(public: true)

      assert_equal 1, GitHub.dogstats.increments("pages.visibility", tags: ["action:public"]).count
      assert_equal 0, GitHub.dogstats.increments("pages.visibility", tags: ["action:private"]).count
    end

    test "soft-deleting a page will add an entry to the audit log" do
      GitHub.flipper[:pages_soft_deletion].enable
      page = create(:page)

      events = subscribe "repo.pages_soft_delete"
      page.soft_delete!
      assert event = events.pop
    end

    test "restoring soft-deleted page will add an entry to the audit log" do
      GitHub.flipper[:pages_soft_deletion].enable
      page = create(:page)
      page.soft_delete!

      events = subscribe "repo.pages_soft_delete_restore"
      page.restore_deleted
      assert event = events.pop, "expected a `repo.pages_soft_delete_restore` event"
      assert event.payload[:soft_deleted_at], "expected a `soft_deleted_at` event field"
    end

    test "when change the repository visibility from private to public, set page's visibility to public" do
      repo = create(:private_repository, name: "Test_Repo")
      repo.owner.update(plan: GitHub::Plan::BUSINESS_PLUS)
      page = make_project_page(repo: repo, private: true)
      refute page.public
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PUBLIC_VISIBILITY) }
      assert page.reload.public
    end

    test "when change the repository visibility from private to public and org disallow public page, unpublish page" do
      GitHub.flipper[:pages_soft_deletion].disable
      org_owner = create(:user)
      org = create(:business_plus_organization, admin: org_owner)
      GitHub.flipper[:private_pages_org_toggle].enable_actor(org_owner)
      org.update(plan: GitHub::Plan::BUSINESS_PLUS)
      org.block_members_from_creating_public_pages(actor: org_owner)
      repo = create(:private_repository, owner: org)
      page = create :private_page, repository: repo
      assert repo.page
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::PUBLIC_VISIBILITY) }
      refute repo.reload.page
    end

    test "when change the repository visibility from private to internal, private page persist" do
      org_owner = create(:user)
      org = create(:organization, admin: org_owner, business: create(:business))
      GitHub.flipper[:private_pages_org_toggle].enable_actor(org_owner)
      org.update(plan: GitHub::Plan::BUSINESS_PLUS)
      org.block_members_from_creating_public_pages(actor: org_owner)
      repo = create(:private_repository, owner: org)
      page = create :private_page, repository: repo
      assert repo.page
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) { repo.set_visibility(actor: repo.owner, visibility: Repository::INTERNAL_VISIBILITY) }
      assert repo.reload.page
    end
  end

  context "auth_token" do
    test "returns a valid signed auth token" do
      session = create :user_session
      repo = create :repository, owner: session.user
      page = create :page, repository: repo
      auth_token = page.auth_token(session: session)

      expected_token = GitHub::Authentication::SignedAuthToken.verify(token: auth_token, scope: "PrivatePages:#{repo.id}")

      assert expected_token.valid?
      assert_instance_of GitHub::Authentication::SignedAuthToken::Session, expected_token
    end

    test "signed auth token has the expected length" do
      session = create :user_session
      repo = create :repository, owner: session.user
      page = create :page, repository: repo
      auth_token = page.auth_token(session: session)

      # make sure Pages SSAT has length expected by the Pages routing infrastructure
      # https://github.com/github/cdn/blob/2e98d1ae3cfae514ee1723fe5e3b444a71e66d69/services/pages/config#L97
      assert_match /\AGHSAT0[ABCDEFGHIJKLMNOPQRSTUVWXYZ234567]{36}\z/, auth_token
    end
  end

  context "set visibility" do
    # skip_with_all_emus because it is specifically testing a Business Plus plan and doesn't apply to EMUs
    test "set page visibility as repository visibility when private page supported", skip_with_all_emus: true do
      user = create(:user, plan: GitHub::Plan::BUSINESS_PLUS)
      private_repo = create(:private_repository, owner: user)
      public_repo = create(:repository, owner: user)
      create(:page, repository: private_repo)

      assert_equal private_repo.public, GitHub.enterprise? ? !private_repo.reload.page.public : private_repo.reload.page.public # no public pages on enterprise

      create(:page, repository: public_repo)
      assert_equal public_repo.public, public_repo.page.public
    end

    test "set page visibility to public when private page not supported" do
      user = create(:user, plan: "pro")
      page = create(:page, repo_signature: :private, owner: user)
      assert page.public
    end

    test "hydro visibility emitted" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      user = create(:user, plan: GitHub::Plan::BUSINESS_PLUS)
      private_repo = create(:private_repository, owner: user)
      page = create(:page, repository: private_repo)
      message = {
        page: Hydro::EntitySerializer.page(page),
        actor: Hydro::EntitySerializer.user(page.owner),
        public: !GitHub.private_pages_enabled?
      }
      assert_hydro_published(message, schema: "github.v1.RepositoryPagesVisibilityChange")
    end
  end

  test "CNAMEs are unique" do
    page2 = @repo.create_page(cname: make_cname_user_page.cname)
    assert_nil page2.cname
  end if GitHub.pages_custom_cnames?

  context "#clear_cname" do
    test "clears the cname from the page" do
      cname_user_page = make_cname_user_page
      cname_user_page.clear_cname
      assert_nil cname_user_page.cname
    end
  end if GitHub.pages_custom_cnames?

  context "#initialize_source_fields" do
    test "is called on save" do
      page = ::FactoryBot.build(:page)

      page.expects(:initialize_source_fields)
      page.save!
    end

    test "is not called on update" do
      page = create(:page, public: true)

      page.expects(:initialize_source_fields).never
      page.update!(public: false)
    end

    test "sets to 'main' when repository default user pages repo and repository default is 'main'" do
      owner = create(:user, login: "pagesuser")
      repository = create(:repository, owner: owner, name: "pagesuser.#{GitHub.pages_host_name_v2}", from_example: :pages_main_only)
      page = ::FactoryBot.build(:page, repository: repository)
      page.save!

      assert_equal "main", page.source_ref_name
      assert_equal "/", page.source_subdir
    end

    test "sets to 'custom' when repository default user pages repo and repository default is 'custom'" do
      owner = create(:user, login: "pagesuser")
      repository = create(:repository, owner: owner, name: "pagesuser.#{GitHub.pages_host_name_v2}", from_example: :pages_custom_default_branch)
      page = ::FactoryBot.build(:page, repository: repository)
      page.save!

      assert_equal "custom", page.source_ref_name
      assert_equal "/", page.source_subdir
    end

    test "sets to 'gh-pages' when not a user pages repo" do
      page = ::FactoryBot.build(:page)
      page.save!

      assert_equal "gh-pages", page.source_ref_name
      assert_equal "/", page.source_subdir
    end
  end

  test "publishes" do
    # Not supporting dynamic workflows
    GitHub.stubs(:actions_enabled?).returns(false)
    page = make_user_page

    # if not GHES, only static only deployment is supported
    if !GitHub.enterprise?
      GitHub.flipper[:pages_static_only_deployment].enable
      Repository.any_instance.stubs(:includes_file?).returns(true)
      GitHub::Pages::PagesDeployerClient.expects(:enqueue).once
      page.publish(page.repository.owner)
    else
      assert_enqueued_with(job: PageBuildJob, args: [page.id, page.repository.owner.id], queue: "page") do
        page.publish(page.repository.owner)
      end
    end
  end

  context "Dynamic workflows (Pages + Actions)", skip_enterprise: true do
    test "Dynamic workflows is supported for legacy billing plans if repository is public" do
      page = make_user_page
      page.create_or_find_deployment_for(page.source_branch)

      GitHub.flipper[:page_build_job_dynamic_workflow_private].enable

      refute page.dynamic_workflow_disabled_reason
      page.repository.owner.plan.stubs(:actions_eligible?).returns(true)
      assert_nil page.dynamic_workflow_disabled_reason
    end

    test "Dynamic workflows is not supported for legacy billing plans if repository is private" do
      repo = create(:private_repository)
      page = create(:page, repository: repo)
      page.create_or_find_deployment_for(page.source_branch)

      GitHub.flipper[:page_build_job_dynamic_workflow_private].enable

      refute page.dynamic_workflow_disabled_reason
      page.repository.owner.plan.stubs(:actions_eligible?).returns(false)
      assert_equal :plan_does_not_support_actions, page.dynamic_workflow_disabled_reason
    end

    test "Dynamic workflows not supported unless the repository allows github actions" do
      page = make_user_page
      page.create_or_find_deployment_for(page.source_branch)

      refute page.dynamic_workflow_disabled_reason
      page.repository.create_actions_allowlist!
      assert_equal :repo_disallows_github_actions, page.dynamic_workflow_disabled_reason
    end

    test "Dynamic workflows not supported if actions is disabled for the repository" do
      page = make_user_page
      page.create_or_find_deployment_for(page.source_branch)

      refute page.dynamic_workflow_disabled_reason
      page.repository.stubs(:actions_disabled_at_any_level?).returns(true)
      assert_equal :repo_disallows_all_actions, page.dynamic_workflow_disabled_reason
    end

    test "Dynamic workflows not supported if business has disabled github-hosted runners" do
      GitHub.flipper[:pages_mariner2_runner_label].disable
      GitHub.flipper[:pages_self_hosted_runner_label].disable
      business = create(:business)
      org = create(:organization, business: business)
      page = create(:page, owner: org)

      Actions::RunnerGroup.expects(:for_entity)
        .with(business, include_hosted_runner_groups: true)
        .returns([
          Actions::RunnerGroup.new(id: 2, name: "GitHub Actions", hosted: true, size: 0)
        ])

      assert_equal :business_uses_only_self_hosted_runners, page.dynamic_workflow_disabled_reason
    end

    test "Dynamic workflows not supported if actions is blocked for the repository or owner" do
      page = make_user_page
      page.create_or_find_deployment_for(page.source_branch)

      GitHub.flipper[:page_build_job_dynamic_workflow_private].enable

      refute page.dynamic_workflow_disabled_reason
      page.repository.stubs(:action_invocation_blocked?).returns(true)
      assert_equal :action_invocation_blocked, page.dynamic_workflow_disabled_reason
    end

    test "Publishes with Actions when dynamic workflows are enabled" do
      skip "Feature is disabled if preview deploys are enabled" if GitHub.flipper[:pages_preview_deployments].enabled?
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      page = make_user_page
      page.create_or_find_deployment_for(page.source_branch)

      execution_id = "75b5f5dd-870f-4a44-8068-70380837fe80"

      Launch::Twirp::DeployerClient.any_instance.expects(:rpc)
        .with(:RunDynamicWorkflow, has_entries({
          repository_id: launch_identity(page.repository),
          actor_id: launch_identity(page.repository.owner),
          integration_name: "pages",
          ref: "main",
          workflow_name: "pages-build-deployment",
          slug: "pages-build-deployment",
          visibility: :VISIBLE,
        }))
        .returns(TwirpResponse.new(
          value: GitHub::Launch::Services::Deploy::RunDynamicWorkflowResponse.new(
            execution_id:,
            workflow_run_id: 123,
          ),
          status: 200,
          call_succeeded: true,
        ))
        .once

      assert page.publish(page.repository.owner, git_ref_name: "main")
      assert_equal 1, GitHub.dogstats.increments("pages.dynamic_workflow.enabled", tags: ["state:success"]).count
    end

    test "Publishes with Actions when dynamic workflows are enabled (simulate launch error)" do
      skip "Feature is disabled if preview deploys are enabled" if GitHub.flipper[:pages_preview_deployments].enabled?
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      page = create(:built_page, :primary)
      page.create_or_find_deployment_for(page.source_branch)

      execution_id = "75b5f5dd-870f-4a44-8068-70380837fe80"

      Launch::Twirp::DeployerClient.any_instance.expects(:rpc)
        .with(:RunDynamicWorkflow, has_entries({}))
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: false,
        ))
        .once

      assert page.publish(page.repository.owner, git_ref_name: "main")
      assert_equal 1, GitHub.dogstats.increments("pages.dynamic_workflow.enabled", tags: ["state:error"]).count
    end

    test "falls back to legacy build when actions integration raises installation error" do
      skip "dotcom environment no longer support legacy page build" unless GitHub.enterprise?

      page = make_user_page
      page.repository.expects(:run_dynamic_workflow).raises(Actions::AppInstaller::InstallationError, "boom")

      assert_enqueued_with(job: PageBuildJob, args: [page.id, page.repository.owner.id], queue: "page") do
        page.publish(page.repository.owner)
      end
    end

    test "do not falls back to legacy build when actions integration raises installation error with reason = spammy_target" do
      page = make_user_page
      page.repository.expects(:run_dynamic_workflow).raises(Actions::AppInstaller::InstallationError.new("boom", :spammy_target))
      assert_enqueued_jobs 0 do
        page.publish(page.repository.owner)
      end
    end

    test "does not run dynamic workflow if pusher is spammy" do
      page = make_user_page
      # make pusher that is spammy
      spammy_pusher = create(:spammy_user, login: "eggs-and-spam")
      assert_enqueued_jobs 0 do
        page.publish(spammy_pusher)
      end
    end

    test "Dynamic workflow rendered correctly" do
      page = make_user_page
      workflow_yaml = page.page_build_yaml("main")
      assert workflow_yaml.include?("on: dynamic")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)

      permissions = workflow_yaml_hash["permissions"]
      assert_equal "read", permissions["contents"]
      assert_equal "write", permissions["pages"]

      assert_nil permissions["actions"] # make sure we aren't requesting any permissions for actions itself

      steps = workflow_yaml_hash["jobs"]["build"]["steps"]
      assert_equal "Build with Jekyll", steps[1]["name"]
      assert_equal "./_site", steps[2]["with"]["path"]

      # should skip build step
      Page.any_instance.stubs(:nojekyll?).returns(true)
      workflow_yaml = page.page_build_yaml("main")
      assert workflow_yaml.include?("name: pages build and deployment")
      assert workflow_yaml.include?("on: dynamic")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      steps = workflow_yaml_hash["jobs"]["build"]["steps"]
      assert_equal "Upload artifact", steps[1]["name"]
      assert_equal ".", steps[1]["with"]["path"]

      # Should explicitly escape the branch name (in concurrency/group)
      assert workflow_yaml.include?("group: \"${{ github.workflow }} @ main\"")  # yaml contains escaped string
      assert_equal "${{ github.workflow }} @ main", workflow_yaml_hash["concurrency"]["group"]  # parsed yaml contains unescaped string
      assert workflow_yaml.include?("ref: \"main\"")  # yaml contains escaped string
      assert_equal "main", steps[0]["with"]["ref"]    # parsed yaml contains unescaped string

      # should render docs folder correctly
      Page.any_instance.stubs(:source_dir).returns("/docs")
      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      steps = workflow_yaml_hash["jobs"]["build"]["steps"]
      assert_equal "./docs", steps[1]["with"]["path"]

      # should render / folder correctly
      Page.any_instance.stubs(:source_dir).returns("/")
      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      steps = workflow_yaml_hash["jobs"]["build"]["steps"]
      assert_equal ".", steps[1]["with"]["path"]

      Page.any_instance.stubs(:nojekyll?).returns(false)
      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      build_steps = workflow_yaml_hash["jobs"]["build"]["steps"]
      assert_equal "actions/jekyll-build-pages@v1", build_steps[1]["uses"]
      assert_equal "actions/upload-pages-artifact@v3", build_steps[2]["uses"]
      deploy_steps = workflow_yaml_hash["jobs"]["deploy"]["steps"]
      assert_equal "actions/deploy-pages@v4", deploy_steps[0]["uses"]

      # should use curl step instead of gh api when specified
      Page.any_instance.stubs(:should_use_gh_api?).returns(true)
      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      telemetry_step = workflow_yaml_hash["jobs"]["report-build-status"]["steps"]
      assert_includes telemetry_step[0]["run"], "gh api"

      Page.any_instance.stubs(:should_use_gh_api?).returns(false)
      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      telemetry_step = workflow_yaml_hash["jobs"]["report-build-status"]["steps"]
      assert_includes telemetry_step[0]["run"], "curl"
    end

    test "runs on ubuntu-latest runners" do
      page = create(:page)

      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      assert_equal "ubuntu-latest", workflow_yaml_hash["jobs"]["deploy"]["runs-on"]
      assert_equal "ubuntu-latest", workflow_yaml_hash["jobs"]["report-build-status"]["runs-on"]
      assert_equal "ubuntu-latest", workflow_yaml_hash["jobs"]["deploy"]["runs-on"]
    end

    test "runs on self-hosted runners when business has disabled GH hosted runners" do
      business = create(:business)
      org = create(:organization, business: business)
      page = create(:page, owner: org)

      GitHub.flipper[:pages_mariner2_runner_label].enable(business)
      Actions::RunnerGroup.expects(:for_entity)
        .with(business, include_hosted_runner_groups: true)
        .returns([
          Actions::RunnerGroup.new(id: 2, name: "GitHub Actions", hosted: true, size: 0)
        ])

      workflow_yaml = page.page_build_yaml("main")
      workflow_yaml_hash = YAML.safe_load(workflow_yaml)
      assert_equal "mariner2", workflow_yaml_hash["jobs"]["deploy"]["runs-on"]
      assert_equal "mariner2", workflow_yaml_hash["jobs"]["report-build-status"]["runs-on"]
      assert_equal "mariner2", workflow_yaml_hash["jobs"]["deploy"]["runs-on"]
    end
  end

  test "does not publish when repo owner is spammy", skip_enterprise: true do
    spammy_user = create(:spammy_user, login: "spammy")
    page = make_user_page(user: spammy_user)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    assert_equal 0, GitHub.dogstats.increments("pages.build_jobs").count
  end

  test "does not publish when plan doesn't support pages", skip_enterprise: true do
    free_user = create(:user, plan: "free")
    repo = create(:private_repository, owner: free_user)
    page = create :page, repository: repo
    assert_enqueued_jobs 0 do
      page.publish(page.repository.owner)
    end
  end

  test "calling publish on a page using a custom workflow does nothing" do
    page = create :built_page, build_type: :workflow
    assert_enqueued_jobs 0 do
      page.publish(page.repository.owner)
    end
  end

  test "publish works for static only deployment if the page is not a workflow build", skip_enterprise: true do
    GitHub.stubs(:actions_enabled?).returns(false)
    GitHub.flipper[:pages_static_only_deployment].enable
    Repository.any_instance.stubs(:includes_file?).returns(true)

    user = create(:user, plan: "pro")
    repo = create(:repository, owner: user, from_example: :simple)
    page = create :page, repository: repo, source: repo.default_branch, build_type: :legacy

    GitHub::Pages::PagesDeployerClient.expects(:enqueue).once
    page.publish(page.repository.owner)
  end

  test "can be deployed when page is using a custom workflow" do
    page = create :built_page, build_type: :workflow

    ref = "main"
    deploy_page(page, git_ref_name: ref)

    # Test helper only creates a single replica for that deployment
    assert_equal 1, page.deployments.count
    assert_equal 1, Page::Replica.where(page_id: page.id).count
    replica = Page::Replica.where(page_id: page.id).first
    deployment = page.deployments.first
    # Makes sure the deployment belongs to the page
    assert_equal page.id, deployment.page_id
    # Make sure the replica belongs to the deployment
    assert replica.pages_deployment_id, deployment.id
  end

  test "does not publish when private repo and owned by sanctioned user", skip_enterprise: true do
    user = create(:user, plan: "pro")
    repo = create(:private_repository, owner: user)
    page = create :page, repository: repo

    user.trade_controls_restriction.full!

    assert_enqueued_jobs 0 do
      page.publish(page.repository.owner)
    end
  end

  test "does publish public repos for trade restricted users", skip_enterprise: true do
    # Not supporting dynamic workflows
    GitHub.flipper[:pages_static_only_deployment].enable
    Repository.any_instance.stubs(:includes_file?).returns(true)
    GitHub.stubs(:actions_enabled?).returns(false)

    user = create(:user, plan: "pro")
    repo = create(:repository, owner: user, from_example: :simple)
    page = create :page, repository: repo, source: repo.default_branch
    user.trade_controls_restriction.full!

    GitHub::Pages::PagesDeployerClient.expects(:enqueue).once
    page.publish(page.repository.owner)
  end

  test "publishes branch builds" do
    # Not supporting dynamic workflows
    GitHub.stubs(:actions_enabled?).returns(false)
    GitHub.flipper[:pages_preview_deployments].disable
    page = make_user_page

    if GitHub.enterprise?
      assert_enqueued_with(job: PageBuildJob, args: [page.id, page.repository.owner.id, { "git_ref_name" => "branch-build" }], queue: "page") do
        page.publish(page.repository.owner, git_ref_name: "branch-build")
      end
    else
      GitHub.flipper[:pages_static_only_deployment].enable
      Repository.any_instance.stubs(:includes_file?).returns(true)
      GitHub::Pages::PagesDeployerClient.expects(:enqueue).once
      page.publish(page.repository.owner)
    end
  end

  context ".build_in_docker?" do
    test "is false when in enterprise", enterprise_only: true do
      Rails.env.stubs(:production?).returns(true)
      Rails.env.stubs(:development?).returns(true)

      refute Page.build_in_docker?
    end

    test "is false when in test", skip_enterprise: true do
      Rails.env.stubs(:production?).returns(false)
      Rails.env.stubs(:development?).returns(false)
      Rails.env.stubs(:test?).returns(true)

      refute Page.build_in_docker?
    end

    test "is true when not in enterprise and production", skip_enterprise: true do
      Rails.env.stubs(:production?).returns(true)
      Rails.env.stubs(:development?).returns(false)

      assert Page.build_in_docker?
    end

    test "is true when not in enterprise and development", skip_enterprise: true do
      Rails.env.stubs(:production?).returns(false)
      Rails.env.stubs(:development?).returns(true)

      assert Page.build_in_docker?
    end

    test "retry conditions" do
      assert_retry_conditions job: PagesPropagateHttpsRedirectJob, args: [1]
    end
  end

  test "pages list latest build artifact with count", skip_enterprise: true do
    page = make_dotcom_page
    pages_repo = page.repository
    artifact_count = 3
    i = 0
    until i >= artifact_count  do
      check_suite = create(
        :check_suite_for_actions_app,
        :success,
        repository: pages_repo,
        creator: @github_org,
        name: "pages build and deployment",
        event: "push"
      )
      artifact = create(:artifact, check_suite: check_suite, name: "github-pages")
      i += 1
    end
    previous_id = page.latest_artifact.id + 1
    assert_equal artifact_count, page.latest_artifacts(limit: artifact_count).count
    page.latest_artifacts(limit: artifact_count).each do |artifact|
      assert artifact.id < previous_id
      previous_id = artifact.id
    end
  end

  test "intialize pages environment for legacy build type", skip_enterprise: true do
    page = make_arbitrary_branch_page
    repo = page.repository
    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal page.source_branch, env.branch_policy_gate.branch_policies.first.name
  end

  test "intialize pages environment for workflow build type", skip_enterprise: true do
    page = create :built_page, owner: @github, build_type: :workflow
    repo = page.repository

    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal repo.default_branch, env.branch_policy_gate.branch_policies.first.name
  end

  test "set pages environment when switching from workflow build type to legacy build_type", skip_enterprise: true do
    page = create :built_page, owner: @github, build_type: :workflow
    repo = page.repository

    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal repo.default_branch, env.branch_policy_gate.branch_policies.first.name

    page.update(build_type: "legacy", source_ref_name: "main2", source_subdir: "/")
    assert_equal 2, env.reload.branch_policy_gate.branch_policies.count
    assert env.branch_policy_gate.branch_policies.map { |policy| policy.name }.include?("main2")
  end

  test "set pages environment when switching from build type to workflow build_type", skip_enterprise: true do


    page = make_arbitrary_branch_page
    repo = page.repository
    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal page.source_branch, env.branch_policy_gate.branch_policies.first.name
    page.update(build_type: "workflow")
    assert_equal 2, env.reload.branch_policy_gate.branch_policies.count
    assert env.branch_policy_gate.branch_policies.map { |policy| policy.name }.include?(repo.default_branch)
  end

  test "set pages environment when switching from build type", skip_enterprise: true do


    page = make_arbitrary_branch_page
    repo = page.repository
    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal page.source_branch, env.branch_policy_gate.branch_policies.first.name
    page.update(build_type: "workflow")
    assert_equal 2, env.reload.branch_policy_gate.branch_policies.count
    assert env.branch_policy_gate.branch_policies.map { |policy| policy.name }.include?(repo.default_branch)
  end

  test "set pages environment when switching source in legacy build type", skip_enterprise: true do


    page = make_arbitrary_branch_page
    repo = page.repository
    refute repo.environments.empty?
    env = repo.environments.first
    skip "environment protection rule disabled" unless env.repository.can_use_deployment_protected_branch?
    assert_equal "github-pages", env.name
    refute env.branch_policy_gate.branch_policies.empty?
    assert_equal page.source_branch, env.branch_policy_gate.branch_policies.first.name
    page.update(source_ref_name: "main2", source_subdir: "/")
    assert_equal 2, env.reload.branch_policy_gate.branch_policies.count
    assert env.branch_policy_gate.branch_policies.map { |policy| policy.name }.include?("main2")
  end

  test "delete page will add an entry in page_update table" do
    on_multi_tenant_enterprise # Pages update table only exists in proxima
    GitHub.flipper[:pages_soft_deletion].disable
    page = create :org_owned_proxima_page
    page.destroy

    assert_equal page.id, PageUpdate.last.page_id
    assert_equal "delete_event", PageUpdate.last.event
  end

  test "soft-delete page will add an entry in page_update table" do
    on_multi_tenant_enterprise  # Pages update table only exists in proxima
    GitHub.flipper[:pages_soft_deletion].enable
    page = create :org_owned_proxima_page

    page.soft_delete!

    assert_equal page.id, PageUpdate.last.page_id
    assert_equal "delete_event", PageUpdate.last.event
  end

  test "restoring soft-deleted page will add an entry in page_update table" do
    on_multi_tenant_enterprise # Pages update table only exists in proxima
    GitHub.flipper[:pages_soft_deletion].enable
    page = create :org_owned_proxima_page
    page.soft_delete!

    PageUpdate.destroy_all
    refute PageUpdate.exists?

    page.restore_deleted

    assert_equal page.id, PageUpdate.last.page_id
    assert_equal "update_event", PageUpdate.last.event
  end

  test "update page will add an entry in page_update table" do
    on_multi_tenant_enterprise  # Pages update table only exists in proxima
    page = create :org_owned_proxima_page

    page.update!(subdomain: "some_avo")

    assert_equal page.id, PageUpdate.last.page_id
    assert_equal "update_subdomain_event", PageUpdate.last.event
  end

  context "soft deletion", skip_enterprise: true do
    test "removes its cname" do
      GitHub.flipper[:pages_soft_deletion].enable
      cname = "example.com"
      page = create :page, :with_cname_file, cname: cname

      page.soft_delete!
      assert_nil page.cname
      assert_equal cname, page.deleted_cname
    end

    test "doesn't lose data if deleted twice" do
      GitHub.flipper[:pages_soft_deletion].enable
      cname = "example.com"
      page = create :page, :with_cname_file, cname: cname

      page.soft_delete!
      assert page.deleted_at

      page.soft_delete!
      assert_nil page.cname
      assert_equal cname, page.deleted_cname
    end

    test "restoring a deleted page restores its cname" do
      GitHub.flipper[:pages_soft_deletion].enable
      cname = "example.com"
      page = create :page
      page.update!(deleted_at: Time.zone.now, deleted_cname: cname)

      page.restore_deleted
      assert_equal cname, page.cname
      assert_nil page.deleted_cname
    end

    test "restoring a deleted page works even if cname is taken" do
      GitHub.flipper[:pages_soft_deletion].enable
      cname = "example.com"
      page = @repo.create_page!(deleted_at: Time.zone.now, deleted_cname: cname)

      another_page = create(:page, cname: cname)

      page.restore_deleted
      assert_nil page.deleted_at
      assert_nil page.deleted_cname
      assert_nil page.cname
    end

    test "changing a soft-deleted page to visible restores it" do
      GitHub.flipper[:pages_soft_deletion].enable
      page = @repo.create_page!(public: false, deleted_at: Time.zone.now)
      assert page.soft_deleted?
      assert page.private?

      page.update!(public: true)
      assert page.public?
      refute page.soft_deleted?
    end
  end

  context "validation", skip_enterprise: true do
    test "fails when adding a cname to a soft-deleted page" do
      GitHub.flipper[:pages_soft_deletion].enable
      page = create :built_page, build_type: :workflow
      page.update!(deleted_at: Time.zone.now)

      page.update(cname: "happy.me")
      assert page.errors["cname"].presence
      assert_nil page.reload.cname
    end

    test "fails when adding a cname while soft-deleting a page" do
      GitHub.flipper[:pages_soft_deletion].enable

      page = create :page

      page.update(cname: "happy.me", deleted_at: Time.zone.now)
      assert page.errors["cname"].presence
      assert_nil page.reload.cname
      assert_nil page.reload.deleted_at
    end

    test "fails when soft-deleting a page without removing its cname" do
      GitHub.flipper[:pages_soft_deletion].enable

      page = create :page, :with_cname_file, cname: "happy.me"

      page.update(deleted_at: Time.zone.now)
      assert page.errors["cname"].presence
      assert_nil page.reload.deleted_at
    end

    test "fails when setting deleted_cname to a live page" do
      GitHub.flipper[:pages_soft_deletion].enable

      page = create :page

      page.update(deleted_cname: "happy.me")
      assert page.errors["deleted_cname"].presence
      assert_nil page.reload.deleted_cname
    end

    test "fails when restoring a page without removing its deleted_cname" do
      GitHub.flipper[:pages_soft_deletion].enable

      page = create :page
      page.update!(deleted_at: Time.zone.now, deleted_cname: "happy.me")

      page.update(deleted_at: nil)
      assert page.reload.errors["deleted_cname"]
      assert page.reload.deleted_at
    end
  end
end
