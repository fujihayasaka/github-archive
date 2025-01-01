# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPageCreationTest < GitHub::TestCase
  include PageHelper

  fixtures do
    @owner = create(:user, login: "johndoe")
    @repo  = create(:repository)
  end

  setup do
    GitHub.flipper[:pages_github_app].disable
    example_repo :page_less_repo, @repo
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def reset_owner(repo)
    Repository.where(id: repo.id).update_all(owner_id: 0)
    repo.reload
  end

  def pages_create_options
    {
      name:       "Page Name",
      tagline:    "Page tagline here",
      body:       "This is the page body."
    }
  end

  context "repo names" do
    test "host name'd repos are user pages repos" do
      user = create(:user)
      repo = create(:repository, name: "#{user}.#{GitHub.host_name}", owner: user)
      assert_predicate repo, :is_user_pages_repo?
    end

    test ".com repos are user pages repos" do
      user = create(:user)
      repo = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v1}", owner: user)
      assert_predicate repo, :is_user_pages_repo?
    end

    test ".io repos are user pages repos" do
      user = create(:user)
      repo = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v2}", owner: user)
      assert_predicate repo, :is_user_pages_repo?
    end

    test "random repo names are not user pages repos" do
      repo = create(:repository, name: "#{@owner}.example.com", owner: @owner)
      refute_predicate repo, :is_user_pages_repo?
    end

    test "primary status survives rename" do
      user = create(:user)
      repo = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v1}", owner: user)
      repo.rename "#{user}.#{GitHub.pages_host_name_v2}"
      assert_predicate repo, :is_user_pages_repo?
    end

    test "not user pages repo if owner is nil" do
      repo = create(:repository, name: "fern-kunze.#{GitHub.host_name}")
      reset_owner(repo)
      refute_predicate repo, :is_user_pages_repo?
    end

    test "knows when an owner owns a user pages repo" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "#{user}.#{GitHub.pages_host_name_v2}")
      assert_predicate repo, :owner_owns_new_user_pages_repo?
    end

    test "knows when a owner doesn't own a user pages repo" do
      repo = create(:repository)
      refute_predicate repo, :owner_owns_new_user_pages_repo?
    end

    test "owner_owns_new_user_pages_repo? doesn't blow up if owner no longer exists" do
      repo = create(:repository)
      reset_owner(repo)
      refute_predicate repo, :owner_owns_new_user_pages_repo?
    end

    unless GitHub.enterprise?
      test "knows when a repo is a new user pages repo" do
        user = create(:user)
        repo = create(:repository, owner: user, name: "#{user}.#{GitHub.pages_host_name_v2}")
        assert_predicate repo, :name_matches_new_user_pages?
        refute_predicate repo, :name_matches_old_user_pages?
      end

      test "name_matches_new_user_pages? doesn't blow up if owner no longer exists" do
        user = create(:user)
        repo = create(:repository, owner: user, name: "#{user}.#{GitHub.pages_host_name_v2}")
        reset_owner(repo)
        refute_predicate repo, :name_matches_new_user_pages?
      end

      test "knows when a repo is a old user pages repo" do
        user = create(:user)
        repo = create(:repository, owner: user, name: "#{user}.#{GitHub.pages_host_name_v1}")
        assert_predicate repo, :name_matches_old_user_pages?
        refute_predicate repo, :name_matches_new_user_pages?
      end

      test "name_matches_old_user_pages? doesn't blow up if owner no longer exists" do
        user = create(:user)
        repo = create(:repository, owner: user, name: "#{user}.#{GitHub.pages_host_name_v1}")
        reset_owner(repo)
        refute_predicate repo, :name_matches_old_user_pages?
      end
    end
  end

  if GitHub.pages_custom_cnames?
    test "detects cname'd user pages repos" do

      page = create(:user_page, cname: "example1.com")
      assert_predicate page.repository, :is_cname_user_pages_repo?

      page = create(:page, cname: "example2.com")
      refute_predicate page.repository, :is_cname_user_pages_repo?

      page = create(:built_page, cname: "example3.com", source_ref_name: "master")
      refute_predicate page.repository, :is_cname_user_pages_repo?

      page = create(:page)
      refute_predicate page.repository, :is_cname_user_pages_repo?
    end
  end

  context "pages branch" do
    test "correctly determines the pages branch for user pages" do
      user = create(:user)
      repo = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v2}", owner: user)
      assert_equal repo.default_branch, repo.pages_branch
    end

    test "correctly determins the pages branch for project pages" do
      repo = create(:repository)
      assert_equal "gh-pages", repo.pages_branch
    end

    test "can be nil when page is using a workflow" do

      repo = create(:repository)
      page = create(:page, repository: repo)
      page.update_attribute(:build_type, "workflow")
      assert_nil repo.pages_branch
    end
  end

  context "has_gh_pages?" do
    test "knows when a project page repo has a pages branch" do
      page = create :built_page
      assert_predicate page.repository, :has_gh_pages?
    end

    test "knows when a user page repo has a pages branch" do
      page = create :user_page, :built
      assert_predicate page.repository, :has_gh_pages?
    end

    test "knows when a repo doesn't have a pages branch" do
      repo = create(:repository)
      refute_predicate repo, :has_gh_pages?
    end

    if GitHub.pages_custom_cnames?
      test "knows a old-user page isn't a pages repo" do
        user  = create(:user)
        repo  = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v1}", owner: user)
        create :page, example_repo: :pages_with_main, repository: repo
        repo2 = create(:repository, name: "#{user}.#{GitHub.pages_host_name_v2}", owner: user)
        create :page, example_repo: :pages_with_main, repository: repo2

        refute_predicate repo, :has_gh_pages?
        refute_predicate repo, :is_user_pages_repo?

        assert_predicate repo2, :has_gh_pages?
        assert_predicate repo2, :is_user_pages_repo?
      end
    end
  end

  test "knows when a repo is a generated repo" do
    page = create :built_page
    repo = page.repository
    refute_predicate repo, :has_generated_page?
    repo.pages_create(repo.owner, pages_create_options, true)
    assert_predicate repo, :has_generated_page?
  end

  test "regular repo starts with no gh-pages branch" do
    assert_equal %w(cf48e6e91d3cf850418bd76bbb00e3c1129bbb25),
      @repo.revision_list(@repo.ref_to_sha("master"))
    refute_predicate @repo, :has_gh_pages?
  end

  test "returns the pages host name" do
    assert_equal GitHub.pages_host_name_v2, @repo.pages_host_name
  end

  context "pages url" do
    if GitHub.enterprise? && !GitHub.subdomain_isolation?
      test "enterprise without subdomain isolation" do
        expected = "https://#{GitHub.pages_host_name_v2}/pages/#{@repo.owner}/#{@repo.name}/"
        assert_equal expected, @repo.gh_pages_url
      end
    end

    if GitHub.enterprise? && GitHub.subdomain_isolation?
      test "enterprise with subdomain isolation" do
        expected = "http://#{GitHub.pages_host_name_v2}/#{@repo.owner}/#{@repo.name}/"
        assert_equal expected, @repo.gh_pages_url
      end
    end

    if !GitHub.enterprise?
      test "dotcom" do
        expected = "http://#{@repo.owner}.#{GitHub.pages_host_name_v2}/#{@repo.name}/"
        assert_equal expected, @repo.gh_pages_url
      end
    end
  end

  context "pages_create" do
    test "doesn't allow overriding" do
      page = create :built_page
      assert_raises(RuntimeError, "gh-pages branch already exists") do
        page.repository.pages_create(page.owner, pages_create_options)
      end
      refute_predicate page.repository, :has_generated_page?
    end

    test "allows overriding" do
      page = create :page
      page.repository.pages_create(page.owner, pages_create_options, true)
      assert_predicate page.repository, :has_generated_page?
    end

    test "creates a new page" do
      user = create(:user)
      repo = create(:repository, owner: user)
      repo.pages_create(user, pages_create_options)
      assert_predicate repo.reload, :has_generated_page?
    end
  end

  context "rebuild_pages" do
    test "deletes the pages site if no pages branch exists" do
      repo = create(:repository)
      repo.page = create :page
      repo.save!
      repo.rebuild_pages
      assert_nil repo.reload.page
    end

    test "triggers an automatic app installation when the Pages installation doesn't exist" do
      skip "Feature behind a flipper flag still" if GitHub.enterprise?
      page = create :built_page
      repo = page.repository
      GitHub.flipper[:pages_github_app].enable_actor(repo)
      expected_originator = {
        page_id: page.id,
        pusher_id: page.owner.id,
        git_ref_name: nil,
      }
      AutomaticAppInstallation.expects(:trigger).with do |args|
        assert_equal :page_build, args[:type]
        assert_equal expected_originator, args[:originator]
        assert_equal repo.id, args[:actor].id
      end

      assert_enqueued_jobs 0 do
        repo.rebuild_pages
      end
    end

    test "rebuilds the page when the Pages Installation does exist" do
      skip "Feature behind a flipper flag still" if GitHub.enterprise?
      skip "Feature is disabled if preview deploys are enabled" if GitHub.flipper[:pages_preview_deployments].enabled?
      page = create :built_page
      repo = page.repository
      GitHub.flipper[:pages_github_app].enable_actor(repo)
      repo.expects(:pages_integration_installation_exists?).returns(true)
      ensure_page_published(page: page, publisher: nil, ref: nil)
    end

    test "rebuilds the page" do
      page = create :built_page
      ensure_page_published(page: page, publisher: nil, ref: nil)
    end

    test "rebuilds the page as another user" do
      page = create :built_page
      user = create(:user)
      ensure_page_published(page: page, publisher: user, ref: page.source)
    end

    test "rebuilds the page with an alternate branch" do
      skip "Feature is disabled if preview deploys are enabled" if GitHub.flipper[:pages_preview_deployments].enabled?
      page = create :built_page
      ensure_page_published(page: page, publisher: nil, ref: "branch-build")
    end

    test "does not rebuild the page if no page & publisher is not an admin" do
      # We make the page here this way since we need the repo to be both
      # online? and have a head matching the pages branch. We get that for
      # free with this method.
      GitHub.flipper[:pages_soft_deletion].disable
      page = create :page
      repo = page.repository
      repo.page.destroy
      repo.reload
      random_user = create(:user)
      assert_enqueued_jobs 0 do
        assert_nil repo.page
        refute repo.rebuild_pages(random_user)
        assert_nil repo.page
      end
    end

    test "does not publisher is not an admin" do
      # We make the page here this way since we need the repo to be both
      # online? and have a head matching the pages branch. We get that for
      # free with this method.
      GitHub.flipper[:pages_soft_deletion].enable
      page = create :page
      repo = page.repository
      now = Time.zone.now.round
      Timecop.freeze(now) do
        repo.page.soft_delete!
        repo.reload
        random_user = create(:user)

        assert_enqueued_jobs 0 do
          assert_equal now.to_date, repo.page.deleted_at.to_date
          refute repo.rebuild_pages(random_user)
          assert_equal now.to_date, repo.page.deleted_at.to_date
        end
      end
    end

    test "rebuilds the page if no page & the publisher is staff" do
      skip "Feature is disabled if preview deploys are enabled" if GitHub.flipper[:pages_preview_deployments].enabled?
      # We make the page here this way since we need the repo to be both
      # online? and have a head matching the pages branch. We get that for
      # free with this method.
      GitHub.flipper[:pages_soft_deletion].disable
      page = create :built_page
      repo = page.repository
      repo.page.destroy
      staff_user = create(:staff_admin_user)
      assert_nil repo.reload.page
      ensure_page_published(page: page, publisher: staff_user, ref: page.source)
      refute_nil repo.reload.page, "Page should have been created"
    end

    test "does not rebuild a free private repo page that has already been destroyed", skip_enterprise: true do
      GitHub.flipper[:pages_soft_deletion].disable
      free_private_repo = create(:private_repository, owner: @owner)
      page = create :page, repository: free_private_repo
      free_private_repo.page.destroy
      free_private_repo.reload
      assert_enqueued_jobs 0 do
        assert_nil free_private_repo.page
        refute free_private_repo.rebuild_pages(@owner)
        assert_nil free_private_repo.page
      end
    end

    test "does not trigger rebuild if using workflow build type" do

      page = create :built_page, build_type: "workflow"
      assert_enqueued_jobs 0 do
        refute page.repository.rebuild_pages
      end
    end
  end

  context "pages build success" do
    test "knows when a build was successful" do
      page = create(:built_page)
      assert_predicate page.repository.reload, :gh_pages_success?, "expected build to succeed"
    end

    test "knows a repo without a page isn't successful" do
      repo = create(:repository)
      refute_predicate repo, :gh_pages_success?
    end

    test "knows a repo without any builds isn't succesful" do
      page = create(:page)
      refute_predicate page.repository, :gh_pages_success?
    end

    test "knows a repo with an errored build isn't successful" do
      page = create(:page, :errored)
      refute_predicate page.repository, :gh_pages_success?
    end
  end

  context "pages build errors" do
    test "knows a repo without a page isn't errored" do
      repo = create(:repository)
      refute_predicate repo, :gh_pages_error?
    end

    test "knows a repo without any builds isn't errored" do
      page = create(:page)
      refute_predicate page.repository, :gh_pages_error?
    end

    test "knows a repo with a successful build isn't errored" do
      page = create(:built_page)
      refute_predicate page.repository, :gh_pages_error?
    end

    test "knows a repo that's errored is errored" do
      page = create(:page, :errored)
      assert_predicate page.repository, :gh_pages_error?
    end

    test "returns the build error" do
      page = create(:page, :errored)
      assert_equal "Build failed", page.repository.gh_pages_error
    end

    test "doesn't return anything if there is no error" do
      page = create(:page)
      assert_nil page.repository.gh_pages_error

      page.builds.create(pusher: page.owner, status: "built")
      assert_nil page.repository.gh_pages_error
    end
  end

  test "returns the last build" do
    page = create(:page, :errored)
    assert_equal "Build failed", page.repository.gh_pages_last_build.error
  end

  context "rebuilder" do
    test "knows the owner can rebuild" do
      repo = create(:repository)
      assert_equal repo.owner, repo.gh_pages_rebuilder(repo.owner)
    end

    test "knows orgs can't build" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      assert_nil repo.gh_pages_rebuilder(org)
    end

    test "returns the last builder" do
      page = create(:page, :errored)
      repo = page.repository
      assert_equal repo.owner, repo.gh_pages_rebuilder
    end

    test "doesn't return the last builder if it's an org" do
      org = create(:organization)
      page = create(:page, :errored, owner: org, builder: org)
      assert_nil page.repository.gh_pages_rebuilder
    end

    test "knows users with pull rights can push" do
      repo = create(:public_repository)
      user = create(:user)
      assert_equal user, repo.gh_pages_rebuilder(user)
    end

    test "knows users without pull rights can't push" do
      repo = create(:private_repository)
      user = create(:user)
      assert_nil repo.gh_pages_rebuilder(user)
    end

    test "knows the staff user can't build" do
      page = create :private_page, :built
      page.builds.create(pusher: User.staff_user, status: "built")
      assert_equal page.repository.owner, page.repository.gh_pages_rebuilder(User.staff_user)
    end if GitHub.guard_audit_log_staff_actor?

    test "knows a repo is rebuildable" do
      repo = create(:repository)
      assert repo.gh_pages_rebuildable?(repo.owner)
    end

    test "knows a repo isn't rebuildable" do
      repo = create(:private_repository)
      refute repo.gh_pages_rebuildable?
    end
  end

  context "org_members_can_create_pages" do
    test "returns true if owner is user" do
      repo = create(:repository)
      assert repo.org_members_can_create_pages?
    end

    test "returns true if an org allows pages creation" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_pages(actor: org.owner)

      assert repo.org_members_can_create_pages?
    end

    test "returns false if an org blocks pages creation" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.block_members_from_creating_pages(actor: org.owner)

      refute repo.org_members_can_create_pages?
    end

    test "returns true if an org allows public pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable

      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_public_pages(actor: org.owner)

      assert repo.org_members_can_create_pages?(visibility: :public)
    end

    test "returns false if an org blocks public pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable

      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_pages(actor: org.owner)

      assert repo.org_members_can_create_pages?(visibility: :public)
    end

    test "returns true if an org allows private pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable

      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_pages(actor: org.owner)

      assert repo.org_members_can_create_pages?(visibility: :private)
    end

    test "returns true if an org blocks private pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable

      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_pages(actor: org.owner)

      assert repo.org_members_can_create_pages?(visibility: :private)
    end
  end

  context "org_members_can_create_public_pages" do
    test "returns true if an org allows public pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_public_pages(actor: org.owner)

      assert repo.org_members_can_create_public_pages?
    end

    test "returns false if an org blocks public pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.block_members_from_creating_public_pages(actor: org.owner)

      refute repo.org_members_can_create_public_pages?
    end

    test "returns false if repo is public" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.block_members_from_creating_public_pages(actor: org.owner)

      refute repo.can_create_page?(actor: org.owner)
    end

    test "returns false for user pages repos if repo is private" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:private_repository, owner: org, name: "#{org}.#{GitHub.host_name}")

      org.block_members_from_creating_public_pages(actor: org.owner)

      refute repo.can_create_page?(actor: org.owner)
    end
  end

  context "org_members_can_create_private_pages" do
    test "returns true if an org allows private pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.allow_members_to_create_private_pages(actor: org.owner)

      assert repo.org_members_can_create_private_pages?
    end

    test "returns false if an org blocks private pages creation" do
      GitHub.flipper[:private_pages_org_toggle].enable
      org = create(:organization)
      repo = create(:repository, owner: org)

      org.block_members_from_creating_private_pages(actor: org.owner)

      refute repo.org_members_can_create_private_pages?
    end
  end

  context "org_members_can_publish_pages" do
    context "private_pages_org_toggle enabled" do
      test "returns true if a page already exists" do
        GitHub.flipper[:private_pages_org_toggle].enable

        org = create(:organization)
        repo = create(:repository, owner: org)
        create :page, repository: repo

        org.block_members_from_creating_public_pages(actor: org.owner)
        org.block_members_from_creating_private_pages(actor: org.owner)

        assert repo.org_members_can_publish_pages?
      end

      test "returns true if an org allows pages creation" do
        GitHub.flipper[:private_pages_org_toggle].enable

        org = create(:organization)
        repo = create(:repository, owner: org)

        org.allow_members_to_create_public_pages(actor: org.owner)

        assert repo.org_members_can_publish_pages?
      end

      test "returns false an org blocks pages creation" do
        GitHub.flipper[:private_pages_org_toggle].enable

        org = create(:organization)
        repo = create(:repository, owner: org)

        org.block_members_from_creating_public_pages(actor: org.owner)
        org.block_members_from_creating_private_pages(actor: org.owner)

        refute repo.org_members_can_publish_pages?
      end
    end

    context "private_pages_org_toggle disabled" do
      test "returns true if a page already exists" do
        GitHub.flipper[:private_pages_org_toggle].disable

        org = create(:organization)
        repo = create(:repository, owner: org)
        create :page, repository: repo

        org.block_members_from_creating_pages(actor: org.owner)

        assert repo.org_members_can_publish_pages?
      end

      test "returns true if an org allows pages creation" do
        GitHub.flipper[:private_pages_org_toggle].disable

        org = create(:organization)
        repo = create(:repository, owner: org)

        org.allow_members_to_create_pages(actor: org.owner)

        assert repo.org_members_can_publish_pages?
      end

      test "returns false an org blocks pages creation" do
        GitHub.flipper[:private_pages_org_toggle].disable

        org = create(:organization)
        repo = create(:repository, owner: org)

        org.block_members_from_creating_pages(actor: org.owner)

        refute repo.org_members_can_publish_pages?
      end
    end
  end

  test "creates gh-pages branch with standard page" do
    @repo.pages_create(@repo.owner, pages_create_options)

    master = @repo.heads.find("master")
    assert_equal %w(cf48e6e91d3cf850418bd76bbb00e3c1129bbb25), @repo.revision_list(master.target_oid)

    pages = @repo.heads.find("gh-pages")
    refute_empty @repo.revision_list(pages.target_oid)
    assert_predicate @repo, :has_gh_pages?
    assert_predicate @repo, :has_generated_page?
  end

  def ensure_page_published(page:, publisher:, ref:)
    publisher ||= page.owner
    if GitHub.enterprise?
      # newly created page with fake page id but not really in the db
      if page.repository&.page.nil?
        assert_enqueued_with job: PageBuildJob, queue: "page" do
          page.repository.rebuild_pages(publisher, git_ref_name: ref)
        end
        return
      end
      expected_args = [page.id, publisher.id]
      expected_args << { "git_ref_name" => ref } if ref
      assert_enqueued_with job: PageBuildJob, args: expected_args, queue: "page" do
        page.repository.rebuild_pages(publisher, git_ref_name: ref)
      end
    else
      ref ||= page.source
      Page.any_instance.expects(:publish).with(publisher, git_ref_name: ref).once
      page.repository.rebuild_pages(publisher, git_ref_name: ref)
    end
  end
end
