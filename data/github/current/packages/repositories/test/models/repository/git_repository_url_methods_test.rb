# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryGitRepositoryUrlMethodsBehaviorTest < GitHub::TestCase
  fixtures do
    unless GitHub.enterprise?
      emu = create(:emu)
      @business = emu.enterprise_managed_business
    end
    @owner = create(:business_plus_org, login: "owner")
    @repo = create(:repository, name: "some-repo", owner: @owner)
    @user = create(:user, login: "defunkt")
    @gist = create(:gist, owner: @user)
  end

  setup do
    @wiki = @repo.unsullied_wiki
  end

  context "repo with host name" do
    test "ssh url" do
      assert_equal "git@github.com:owner/some-repo.git", @repo.ssh_url
    end

    test "ssh url for owner with ssh cert" do
      create(:ssh_certificate_authority, owner: @owner)
      assert_equal "org-#{@owner.id}@github.com:owner/some-repo.git", @repo.ssh_url
    end

    test "clone host name" do
      assert_equal "github.com", @repo.clone_host_name
    end
  end

  context "repo ssh url" do
    test "use tenant slug prefix and name_with_display_owner for ssh url for repo in Proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "#{@business&.slug}@#{@repo.clone_host_name}:#{@repo.name_with_display_owner}.git", @repo.ssh_url
      end
    end

    test "use tenant slug prefix and name_with_display_owner for ssh url for repo with ssh cert in Proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        create(:ssh_certificate_authority, owner: @owner)
        assert_equal "#{@business&.slug}_#{@owner.id}@#{@repo.clone_host_name}:#{@repo.name_with_display_owner}.git", @repo.ssh_url
      end
    end

    test "ssh url for owner with ssh cert in dotcom" do
      create(:ssh_certificate_authority, owner: @owner)
      assert_equal "org-#{@owner.id}@#{@repo.clone_host_name}:#{@repo.name_with_display_owner}.git", @repo.ssh_url
    end

    test "use git prefix and name_with_display_owner for ssh url for repo in dotcom" do
      assert_equal "git@#{@repo.clone_host_name}:#{@repo.name_with_display_owner}.git", @repo.ssh_url
    end
  end

  # should be same in proxima and dotcom
  context "repo http url" do
    test "use repo.name_with_display_owner for Proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "https://#{@repo.clone_host_name}/#{@repo.name_with_display_owner}.git", @repo.http_url
      end
    end

    test "use repo.name_with_display_owner for dotcom" do
      assert_equal "https://#{@repo.clone_host_name}/#{@repo.name_with_display_owner}.git", @repo.http_url
    end
  end

  context "repo short git path" do
    test "use repo.name_with_display_owner for Proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal @repo.name_with_display_owner, @repo.short_git_path
      end
    end

    test "use repo.name_with_owner for dotcom" do
      assert_equal @repo.name_with_owner, @repo.short_git_path
    end
  end

  context "wiki ssh url" do
    test "wiki ssh url in proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "#{@business&.slug}@#{@wiki.clone_host_name}:#{@wiki.short_git_path}.git", @wiki.ssh_url
      end
    end

    test "wiki ssh url in dotcom" do
      assert_equal "git@#{@wiki.clone_host_name}:#{@wiki.short_git_path}.git", @wiki.ssh_url
    end
  end

  # should be same in proxima and dotcom
  context "wiki http url" do
    test "wiki http url in proxima", skip_enterprise: true do
      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "https://#{@wiki.clone_host_name}/#{@wiki.short_git_path}.git", @wiki.http_url
      end
    end

    test "wiki http url in dotcom" do
      assert_equal "https://#{@wiki.clone_host_name}/#{@wiki.short_git_path}.git", @wiki.http_url
    end
  end

  test "gist ssh url in dotcom" do
    assert_equal "git@#{@gist.clone_host_name}:#{@gist.short_git_path}.git", @gist.ssh_url
  end

  test "gist http url in dotcom" do
    assert_equal "https://#{@gist.clone_host_name}/#{@gist.short_git_path}.git", @gist.http_url
  end
end
