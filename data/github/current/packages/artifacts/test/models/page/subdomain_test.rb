# typed: true
# frozen_string_literal: true

require "test_helper"

class PageCustomSubdomainTest < GitHub::TestCase
  include PageHelper

  fixtures do
    @business = if GitHub.enterprise?
      create(:global_business)
    else
      create :business, :enterprise_managed_business
    end
  end

  context "dotcom" do
    test "value is formatted correctly" do
      skip unless GitHub.private_pages_enabled?
      page = create :page
      page.subdomain = Page::Subdomain.new(repository: page.repository).value

      assert subdomain_name_in_format?(page)
    end

    test "normalized_repo changes invalid values", skip_in_multitenant_mode: true do
      normalized_subdomains = {
        "UPPERCASE" => "uppercase",
        "foo bar" => "foo-bar",
        "foo.bar" => "foo-bar",
        "foo_bar" => "foo-bar",
        "bad-end-" => "bad-end",
        "-bad-start" => "bad-start",
        "a" * 65 => "a" * 64
      }
      normalized_subdomains.each do |invalid_name, valid_name|
        repo = create :repository, name: invalid_name
        subdomain = Page::Subdomain.new(repository: repo)
        assert_equal subdomain.normalized_repo, valid_name
      end
    end

    test "normalized_repo does not change valid values", skip_in_multitenant_mode: true do
      %w[veridis-quo around-the-world daftpunk].each do |repo_name|
        repo = create :repository, name: repo_name
        subdomain = Page::Subdomain.new(repository: repo)
        assert_equal subdomain.normalized_repo, repo_name
      end
    end

    test "subdomain generated for private pages always within 64 characters", skip_enterprise: true do
      skip unless GitHub.private_pages_enabled?
      page = create :page, public: false, repo_signature: :private
      page.id = 2**64
      subdomain = Page::Subdomain.new(repository: page.repository).for_dotcom_private

      assert subdomain.length < 64
    end
  end

  context "proxima", skip_enterprise: true do
    test "value in proxima is unique even if repo name normalizes to the same value" do
      on_multi_tenant_enterprise(tenant: @business) do
        # Create two repos which will normalize to the same value
        foo1 = create(:private_repository, name: "thecakeis.notalie")
        foo2 = create(:private_repository, owner: foo1.owner, name: "thecakeis-notalie")
        assert Page::Subdomain.new(repository: foo1).normalized_repo == Page::Subdomain.new(repository: foo2).normalized_repo

        create :page, repository: foo1
        create :page, repository: foo2

        hash1 = Digest::SHA256.hexdigest(foo1.name)[0..5]
        hash2 = Digest::SHA256.hexdigest(foo2.name)[0..5]

        # foo1 should be the default subdomain and foo2 should have a hash appended to it
        refute_equal foo1.page.subdomain, foo2.page.subdomain
        refute_includes foo1.page.subdomain, hash1
        assert_includes foo2.page.subdomain, hash2
        assert foo1.page.subdomain.length + 7 == foo2.page.subdomain.length
      end
    end

    test "routeable subdomain in proxima is capped at 63 characters" do
      on_multi_tenant_enterprise(tenant: @business) do
        long_named_repo = create(:private_repository, name: "a" * 64)
        subdomain = create(:page, repository: long_named_repo).subdomain

        routable_subdomain = subdomain.chomp("_#{@business.shortcode}")

        assert_equal routable_subdomain.length, 63
      end
    end
  end
end
