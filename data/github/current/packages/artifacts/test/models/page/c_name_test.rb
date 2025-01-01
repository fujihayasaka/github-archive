# typed: true
# frozen_string_literal: true

require "test_helper"

class PageCNameTest < GitHub::TestCase
  fixtures do
    @janedoe  = create(:user, login: "janedoe")
    @repo     = create(:repository, name: "repo",     owner: @janedoe)
    @page     = @repo.create_page(cname: "janedoe.com")

    # protected domain validation
    @protected_user = create(:user, login: "user")
    @protected_domain = "test.example.com"
    @protected_parent_domain = "example.com"
    protected_repo = create(:repository, name: "repo",     owner: @protected_user)
    @protected_page = protected_repo.create_page(cname: @protected_domain)
  end

  context "format validation" do
    test "is invalid with semicolon on end" do
      assert_raises Page::InvalidCNAME do
        Page::CName.validate_format("foo.example.com;")
      end
    end

    test "is invalid for local host style domains" do
      %w[default include foo this-should-not-work].each do |bad|
        assert_raises Page::InvalidCNAME do
          Page::CName.validate_format(bad)
        end
      end
    end

    test "is invalid with non alpha characters" do
      ["example.com\ngithub.com", "foo.com\nbar", "*.test.com", "test.*"].each do |bad|
        assert_raises Page::InvalidCNAME do
          Page::CName.validate_format(bad)
        end
      end
    end

    test "is invalid with spaces in the domain" do
      ["foo bar", "example . com", " what else.com"].each do |bad|
        assert_raises Page::InvalidCNAME do
          Page::CName.validate_format(bad)
        end
      end
    end

    test "is invalid with periods on beginning or end" do
      [".test.com", "..test.com", "test.com..", "test.com."].each do |bad|
        assert_raises Page::InvalidCNAME do
          Page::CName.validate_format(bad)
        end
      end
    end

    test "is invalid with double periods" do
      ["foo..test.com", "te..st.com"].each do |bad|
        assert_raises Page::InvalidCNAME do
          Page::CName.validate_format(bad)
        end
      end
    end

    test "is valid with unicode characters (including homographs)" do
      assert_nil Page::CName.validate_format("анниковна.рф")
      assert_nil Page::CName.validate_format("exаmple.com")
    end
  end

  test "is invalid for github domains that are squattable" do
    Page::CName::DOMAIN_BLOCKLIST.each do |cname|
      page = Page.new(repository: @repo, cname: cname)
      assert_raises Page::InvalidCNAME do
        Page::CName.new(page, cname).validate
      end
    end
  end

  test "is invalid for non-github-pages to create cnames for github-owned pages" do
    github = create(:organization, login: "github")
    github_repo = create(:repository, name: "repo", owner: github)

    cname = "git-merge.com"
    github_page = Page.create(repository: github_repo, cname: cname)
    page = Page.new(repository: @repo, cname: cname)

    assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
  end

  test "is valid for github pages to create cnames for github-owned pages" do
    github = create :user, login: "github"
    github_repo = create(:repository, name: "repo", owner: github)

    cname = Page::CName::DOMAIN_BLOCKLIST.first
    page = Page.new(repository: github_repo, cname: cname)

    assert Page::CName.new(page, cname).validate
  end

  test "is invalid for cname exceed 255 characters" do
    invalid_cname = "www.superlongggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg.com"
    page = Page.new(repository: @repo, cname: invalid_cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, invalid_cname).validate
    end
    assert_equal "The custom domain cannot exceed 255 characters.", ex.message
  end

  test "is invalid for IP addresses" do
    page = Page.new(repository: @repo, cname: "192.30.252.153")
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, "192.30.252.153").validate
    end
    assert_equal "Your custom domain cannot be an IP address. See #{GitHub.help_url}/articles/troubleshooting-custom-domains/#github-repository-setup-errors for more information.", ex.message
  end

  test "is invalid with numbers as the final octet" do
    ["www.185.199.108.153", "www.185.199.109.153"].each do |bad|
      page = Page.new(repository: @repo, cname: bad)
      assert_raises Page::InvalidCNAME do
        Page::CName.new(page, bad).validate
      end
    end
  end

  test "is invalid for duplicate cname same owner" do
    page = Page.new(repository: @repo)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, "janedoe.com").validate
    end
    assert_equal "The custom domain `janedoe.com` is already taken by another repository in your account. Check out #{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site for information about how to remove this domain from the other repository.", ex.message
  end

  test "is invalid for duplicate cname different owner" do
    different_owner = create(:user)
    repo = create(:repository, owner: different_owner)
    page = repo.create_page(cname: "johndoe.com")
    page = Page.new(repository: @repo)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, "johndoe.com").validate
    end
    assert_equal "The custom domain `johndoe.com` is already taken. If you are the owner of this domain, check out #{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages for information about how to verify and release this domain.", ex.message
  end

  test "is invalid for duplicate cname when repo owned by same org" do
    admin = create(:user)
    org = create(:organization, admin: admin)
    @repo.owner = org
    @repo.save
    repo = create(:repository, owner: org)
    page = Page.new(repository: repo)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, "janedoe.com").validate
    end
    assert_equal "The custom domain `janedoe.com` is already taken by another repository in your organization. Check out #{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site for information about how to remove this domain from the other repository.", ex.message
  end

  test "is invalid for www.www prefix" do
    cname = "www.www.test.org"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "Your custom domain cannot start with 'www.www.'. See #{GitHub.help_url}/articles/troubleshooting-custom-domains/#github-repository-setup-errors for more information.", ex.message
  end

  test "does not allow github.com CNAMEs" do
    cname = "janedoe.github.com"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "does not allow github.io CNAMEs" do
    cname = "janedoe.github.io"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "does not allow github.net CNAMEs" do
    cname = "packages.service.cp1-iad.github.net"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "does not allow githubapp.com CNAMEs" do
    cname = "janedoe.githubapp.com"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "does not allow github.page CNAMEs" do
    cname = "janedoe.github.page"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "does not allow githubusercontent.com CNAMEs" do
    cname = "janedoe.githubusercontent.com"
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "You cannot use custom domains ending with github.io, github.com, github.net, github.page, or githubusercontent.com. Instead, create a repository named janedoe.github.io. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "friendly message for redundant CNAME" do
    cname = "janedoe.github.io"
    @repo.update_attribute(:name, cname)
    page = Page.new(repository: @repo, cname: cname)
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, cname).validate
    end
    assert_equal "Your custom domain was ignored because this repository is automatically hosted from janedoe.github.io already. See #{GitHub.help_url}/articles/setting-up-your-pages-site-repository/", ex.message
  end

  test "is invalid for cname/alt-cname clash" do
    page = Page.new(repository: @repo, cname: "www.janedoe.com")
    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(page, "www.janedoe.com").validate
    end
    assert_equal "The custom domain `www.janedoe.com` is already taken by another repository in your account. Check out #{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site for information about how to remove this domain from the other repository.", ex.message
  end

  test "is invalid for spammy owners" do
    spammy_owner = create(:user, spammy: true)
    spammy_repo = create(:repository, name: "repo", owner: spammy_owner)

    cname = "github.biz"
    spammy_page = Page.new(repository: spammy_repo, cname: cname)

    ex = assert_raises Page::InvalidCNAME do
      Page::CName.new(spammy_page, cname).validate
    end

    assert_equal "You cannot set a custom domain at this time.", ex.message
  end

  context "protected domain validation" do
    test "is valid when the domain is not protected", skip_enterprise: true do
      assert Page::CName.new(@protected_page, @protected_domain).validate
    end

    test "is valid when protected by the page's owner", skip_enterprise: true do
      create(:protected_domain, :unverified, name: @protected_domain) # unrelated conflicting domain
      create(:protected_domain, :verified, name: @protected_domain, owner: @protected_user)
      assert Page::CName.new(@protected_page, @protected_domain).validate
    end

    test "is valid when parent domain is protected by the page's owner", skip_enterprise: true do
      create(:protected_domain, :unverified, name: @protected_parent_domain) # unrelated conflicting domain
      create(:protected_domain, :verified, name: @protected_parent_domain, owner: @protected_user)
      assert Page::CName.new(@protected_page, @protected_domain).validate
    end

    test "is invalid when protected and verified by another owner", skip_enterprise: true do
      create(:protected_domain, :verified, name: @protected_domain)
      ex = assert_raises Page::InvalidCNAME do
        Page::CName.new(@protected_page, @protected_domain).validate
      end

      help_url = "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages"
      assert_equal "You must verify your domain #{@protected_domain} before being able to use it. Check out #{help_url} for more information.", ex.message
    end

    test "is invalid when protected and pending by another owner", skip_enterprise: true do
      create(:protected_domain, :pending, name: @protected_domain)
      ex = assert_raises Page::InvalidCNAME do
        Page::CName.new(@protected_page, @protected_domain).validate
      end

      help_url = "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages"
      assert_equal "You must verify your domain #{@protected_domain} before being able to use it. Check out #{help_url} for more information.", ex.message
    end

    test "is invalid when parent domain is protected and verified by another owner", skip_enterprise: true do
      create(:protected_domain, :verified, name: @protected_parent_domain)

      # Test subdomain + www varient of a subdomain
      [@protected_domain, "www.#{@protected_domain}"].each do |domain|
        ex = assert_raises Page::InvalidCNAME do
          Page::CName.new(@protected_page, domain).validate
        end
        help_url = "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages"
        assert_equal "You must verify your domain #{domain} before being able to use it. Check out #{help_url} for more information.", ex.message
      end
    end

    test "is invalid when parent domain is protected and pending by another owner", skip_enterprise: true do
      create(:protected_domain, :pending, name: @protected_parent_domain)

      # Test subdomain + www varient of a subdomain
      [@protected_domain, "www.#{@protected_domain}"].each do |domain|
        ex = assert_raises Page::InvalidCNAME do
          Page::CName.new(@protected_page, domain).validate
        end
        help_url = "#{GitHub.help_url}/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages"
        assert_equal "You must verify your domain #{domain} before being able to use it. Check out #{help_url} for more information.", ex.message
      end
    end
  end
end if GitHub.pages_custom_cnames?
