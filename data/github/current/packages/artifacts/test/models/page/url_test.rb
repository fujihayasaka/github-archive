# typed: true
# frozen_string_literal: true

require "test_helper"


class PageUrlTest < GitHub::TestCase
  include PageHelper

  # We test the following use cases:
  #
  # 1. A user page (https)
  # 2. A "legacy" user page (http)
  # 3. Project Page (https)
  # 4. User page with CNAME
  # 5. Project page with CNAME
  # 6. Project page that inherits a CNAME from its user page
  # 7. Project page with a CNAME that has a userpage with a CNAME
  # 8. GitHub-owned site (`github.github.io/project`)
  # 9. GitHub-owned site CNAME'd to `foo.github.io`
  #
  # Note: Enterprise instances can have a user or org named "github", but
  # their repos should not gain any special powers
  fixtures do
    @user   = create(:user)

    @user_page          = create(:page, :primary)
    @legacy_user_page   = create(:page, :primary, :repo_before_https)
    @project_page       = create(:page)
    @cname_user_page    = create(:user_page, :with_cname_file, cname: "user-page.com", owner: @user)
    @cname_project_page = create(:page, cname: "project-page.com")
    @inherited_project_page           = create(:page, owner: @user)
    @inherited_project_page_wth_cname = create(:page, owner: @user, cname: "inherited-project-page.biz")

    unless TestEnv.test_in_multitenancy_mode? # An org named github is not allowed in MT mode
      @github = create(:organization, login: "github")
      @github_owned_page  = create(:page, owner: @github)
      @github_dotcom_page = create(:page, owner: @github, cname: "pages.github.com")
    end
  end

  # For each use case, we need to test in the following environments:
  #
  # 1. GitHub.com
  # 2. GitHub Enterprise *without* subdomain isolation
  # 3. GitHub Enterprise *with* subdomain isolation
  #
  # For each scenerio, we want to validate:
  #
  # 1. scheme
  # 2. host
  # 3. path
  # 4. url
  context "full URLs" do
    context "dotcom" do
      test "user page" do
        assert_pages_url @user_page, scheme: "https", host: "#{@user_page.owner}.github.io"
      end

      # Skip for EMUs because EMU owned pages can't be public
      test "legacy user page", skip_with_all_emus: true do
        assert_pages_url @legacy_user_page, scheme: "http", host: "#{@legacy_user_page.owner}.github.io"
      end

      # Skip for EMUs because EMU owned pages can't be public
      test "project page", skip_with_all_emus: true do
        host = "#{@project_page.owner}.github.io"
        path = "/#{@project_page.repository.name}/"
        assert_pages_url @project_page, scheme: "https", host: host, path: path
      end

      test "CNAME'd user page" do
        assert_pages_url @cname_user_page, scheme: "http", host: "user-page.com"
      end

      test "CNAME'd project page" do
        assert_pages_url @cname_project_page, scheme: "http", host: "project-page.com"
      end

      test "underscore in a CNAME" do
        page = create(:page, cname: "user_page.biz")
        assert_equal page.url.to_s, "http://user_page.biz/"
      end

      test "project page with a CNAME'd user page" do
        path = "/#{@inherited_project_page.repository.name}/"
        assert_pages_url @inherited_project_page, scheme: "http", host: "user-page.com", path: path
      end

      test "CNAME'd project page with a CNAME'd user page" do
        assert_pages_url @inherited_project_page_wth_cname, scheme: "http", host: "inherited-project-page.biz"
      end

      # Skip for EMUs because EMU owned pages can't be public, on MT because there are is no github org
      test "GitHub owned page", skip_with_all_emus: true, skip_in_multitenant_mode: true do
        host = "#{@github_owned_page.owner}.github.com"
        path = "/#{@github_owned_page.repository.name}/"
        assert_pages_url @github_owned_page, scheme: "https", host: host, path: path
      end

      test "github owned pages use github.io if they are private", skip_in_multitenant_mode: true do
        skip "not set up for GHE" if GitHub.enterprise?
        @github.update(plan: GitHub::Plan::BUSINESS_PLUS)
        private_page  = create(:private_page, owner: @github)

        assert_equal private_page.url.to_s, "https://#{private_page.subdomain}.pages.github.io/"
      end

      test "CNAME'd GitHub-owned page", skip_in_multitenant_mode: true do
        assert_pages_url @github_dotcom_page, scheme: "https", host: "pages.github.com"
      end

      test "Private Project page uses a subdomain" do
        biz_org = create(:organization)
        biz_org.update(plan: GitHub::Plan::BUSINESS_PLUS)
        page = create(:private_page, owner: biz_org)
        if GitHub.enterprise?
          assert_equal page.url.to_s, "https://#{page.subdomain}.github.io/"
        else
          assert_equal page.url.to_s, "https://#{page.subdomain}.pages.github.io/"
        end
      end
    end if GitHub.pages_custom_cnames?

    context "enterprise" do
      context "with subdomain isolation" do
        test "user page" do
          assert_pages_url @user_page, path: "/#{@user_page.owner}"
        end

        test "legacy user page" do
          assert_pages_url @legacy_user_page, path: "/#{@legacy_user_page.owner}/"
        end

        test "project page" do
          path = "/#{@project_page.owner}/#{@project_page.repository.name}/"
          assert_pages_url @project_page, path: path
        end

        test "CNAME'd user page" do
          assert_pages_url @cname_user_page, path: "/#{@cname_user_page.owner}/"
        end

        test "CNAME'd project page" do
          path = "/#{@cname_project_page.owner}/#{@cname_project_page.repository.name}/"
          assert_pages_url @cname_project_page, path: path
        end

        test "project page with a CNAME'd user page" do
          path = "/#{@inherited_project_page.owner}/#{@inherited_project_page.repository.name}/"
          assert_pages_url @inherited_project_page, path: path
        end

        test "CNAME'd project page with a CNAME'd user page" do
          path = "/#{@inherited_project_page_wth_cname.owner}/#{@inherited_project_page_wth_cname.repository.name}/"
          assert_pages_url @inherited_project_page_wth_cname, path: path
        end

        test "'github' owned page", skip_in_multitenant_mode: true  do
          path = "/#{@github_owned_page.owner}/#{@github_owned_page.repository.name}"
          assert_pages_url @github_owned_page, path: path
        end

        test "CNAME'd 'github'-owned page", skip_in_multitenant_mode: true do
          path = "/#{@github_dotcom_page.owner}/#{@github_dotcom_page.repository.name}/"
          assert_pages_url @github_dotcom_page, path: path
        end
      end if GitHub.subdomain_isolation?

      context "without subdomain isolation" do
        test "user page" do
          assert_pages_url @user_page, path: "/pages/#{@user_page.owner}/"
        end

        test "legacy user page" do
          assert_pages_url @legacy_user_page, path: "/pages/#{@legacy_user_page.owner}/"
        end

        test "project page" do
          path = "/pages/#{@project_page.owner}/#{@project_page.repository.name}/"
          assert_pages_url @project_page, path: path
        end

        test "CNAME'd user page" do
          assert_pages_url @cname_user_page, path: "/pages/#{@cname_user_page.owner}/"
        end

        test "CNAME'd project page" do
          path = "/pages/#{@cname_project_page.owner}/#{@cname_project_page.repository.name}/"
          assert_pages_url @cname_project_page, path: path
        end

        test "project page with a CNAME'd user page" do
          path = "/pages/#{@inherited_project_page.owner}/#{@inherited_project_page.repository.name}/"
          assert_pages_url @inherited_project_page, path: path
        end

        test "CNAME'd project page with a CNAME'd user page" do
          path = "/pages/#{@inherited_project_page_wth_cname.owner}/#{@inherited_project_page_wth_cname.repository.name}/"
          assert_pages_url @inherited_project_page_wth_cname, path: path
        end

        test "'github' owned page", skip_in_multitenant_mode: true do
          path = "/pages/#{@github_owned_page.owner}/#{@github_owned_page.repository.name}/"
          assert_pages_url @github_owned_page, path: path
        end

        test "CNAME'd 'github'-owned page", skip_in_multitenant_mode: true do
          path = "/pages/#{@github_dotcom_page.owner}/#{@github_dotcom_page.repository.name}/"
          assert_pages_url @github_dotcom_page, path: path
        end
      end unless GitHub.subdomain_isolation?
    end if GitHub.enterprise?

    context "proxima" do
      test "proxima_host" do
        on_multi_tenant_enterprise

        page = create(:org_owned_proxima_page)
        assert_equal page.url.host, "#{page.display_subdomain}.#{GitHub.pages_host_name_proxima}"
        # Force re-evaluation of pages_host_name_v2 to verify it matches proxima_host_name
        assert_equal page.url.host, "#{page.display_subdomain}.#{GitHub.pages_host_name_v2}"
      end

      test "proxima does not have have a different url for user pages owned by an org (primary repos dont exist)" do
        on_multi_tenant_enterprise

        user = create :emu
        business = user.enterprise_managed_business
        org = create :organization, business: business, admin: user
        primary_name = "#{org}.#{GitHub.pages_host_name_v2}".downcase
        repo = create(:private_repository, owner: org, name: primary_name)
        page = create(:org_owned_proxima_page, repository: repo)

        assert_equal page.url.to_s, "https://#{page.display_subdomain}.#{GitHub.pages_host_name_proxima}/"
      end

      test "proxima does not have have a different url for user pages owned by emu (primary repos dont exist)" do
        on_multi_tenant_enterprise

        user = create :emu
        business = user.enterprise_managed_business
        org = create :organization, business: business, admin: user
        primary_name = "#{user}.#{GitHub.pages_host_name_v2}".downcase
        repo = create(:repository, owner: user, force_user_owned: true, name: primary_name)
        assert repo.owner.user?
        page = create(:emu_owned_proxima_page, repository: repo)

        assert_equal page.url.to_s, "https://#{page.display_subdomain}.#{GitHub.pages_host_name_proxima}/"
      end
    end
  end

  test "pages host name", skip_in_multitenant_mode: true do
    assert_equal GitHub.pages_host_name_v2, @user_page.url.async_pages_host_name.sync
    assert_equal GitHub.pages_host_name_v1, @github_owned_page.url.async_pages_host_name.sync
  end

  test "default user subdomain", skip_in_multitenant_mode: true do
    assert_equal "#{@user_page.owner}.#{GitHub.pages_host_name_v2}", @user_page.url.async_user_host_name.sync
    assert_equal "#{@github_dotcom_page.owner}.#{GitHub.pages_host_name_v1}", @github_dotcom_page.url.async_user_host_name.sync
  end

  context "default host name" do
    test "a user page without a cname" do
      assert_equal "#{@user_page.owner}.github.io", @user_page.url.async_default_host_name.sync
    end

    test "a user page with a CNAME" do
      assert_equal "#{@cname_user_page.owner}.github.io", @cname_user_page.url.async_default_host_name.sync
    end

    test "a project page without CNAMEs" do
      assert_equal "#{@project_page.owner}.github.io", @project_page.url.async_default_host_name.sync
    end

    test "a project page with a CNAME" do
      assert_equal "#{@cname_project_page.owner}.github.io", @cname_project_page.url.async_default_host_name.sync
    end

    test "project page with CNAME'd user page" do
      assert_equal "user-page.com", @inherited_project_page.url.async_default_host_name.sync
    end

    test "CNAME'd project page with CNAME'd user page" do
      assert_equal "user-page.com", @inherited_project_page_wth_cname.url.async_default_host_name.sync
    end

    test "a github-owned page without a CNAME", skip_in_multitenant_mode: true do
      assert_equal "#{@github_owned_page.owner}.github.com", @github_owned_page.url.async_default_host_name.sync
    end

    test "a GitHub-owned page with a CNAME", skip_in_multitenant_mode: true do
      assert_equal "#{@github_dotcom_page.owner}.github.com", @github_dotcom_page.url.async_default_host_name.sync
    end
  end if GitHub.pages_custom_cnames?

  context "inherited domain" do
    test "returns nil for user pages" do
      assert_nil @user_page.url.async_inherited_cname.sync
    end

    test "returns nil for project pages with no custom user domain" do
      assert_nil @project_page.url.async_inherited_cname.sync
    end

    if GitHub.pages_custom_cnames?
      test "returns the CNAME for project pages inheriting domains from CNAME'd user pages" do
        assert_equal "user-page.com", @inherited_project_page.url.async_inherited_cname.sync
        assert_equal "user-page.com", @inherited_project_page_wth_cname.url.async_inherited_cname.sync
      end
    else
      test "returns nil when custom domains are disabled" do
        assert_nil @inherited_project_page.url.async_inherited_cname.sync
      end
    end
  end

  test "it stores the page" do
    assert_equal @user_page, @user_page.url.page
  end
end
