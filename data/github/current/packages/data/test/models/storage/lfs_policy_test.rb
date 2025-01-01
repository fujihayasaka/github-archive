# typed: true
# frozen_string_literal: true

require "test_helper"

class StorageLfsPolicyTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @owner = create :user
    @repo = create :repository, owner: @owner
    @key = create :public_key, repository: @repo

    @cust_owner = create :user
    @customer = create(:customer_account, user: @cust_owner).customer
    @cust_repo = create :repository, owner: @cust_owner

    unless GitHub.enterprise?
      @org_owner = create(:emu, :owner)
      @business = @org_owner.enterprise_managed_business
      @business_org = create(:organization, business: @business)
      @org_repo = create :repository, owner: @business_org
    end
  end

  test "stats for download" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    blob = create :media_blob, state: 3
    Storage::LfsPolicy.new(blob).download_link

    assert stat = stats.timings("storage_policy.url").last
    assert_includes stat.tags, "policy:lfs"
    assert_includes stat.tags, "model:media/blob"
    assert_includes stat.tags, "op:download"
  end

  test "download link expiry" do
    blob = create :media_blob, state: 3
    link = Storage::LfsPolicy.new(blob).download_link

    assert_equal 3600, link[:expires_in]
    time_diff = Time.parse(link[:expires_at]) - Time.now
    assert time_diff <= 3600, "#{Time.now.inspect} => #{link[:expires_at]} = #{time_diff}s"
  end

  # At the moment, the Storage::LfsPolicy inherits its #lfs_upload_link()
  # method from its Storage::S3Policy ancestor class.  For completeness,
  # though, we add a set of tests of the method dedicated to LFS usage.
  #
  # Note also that the expiry time is just advisory for the Git LFS client,
  # as signed URLs are always considered expired by both S3 and Memory Alpha
  # after a fixed time period of 15 minutes.
  test "upload link expiry" do
    blob = create :media_blob, state: 3
    link = Storage::LfsPolicy.new(blob).lfs_upload_link

    assert_equal 900, link[:expires_in]
    time_diff = Time.parse(link[:expires_at]) - Time.now
    assert time_diff <= 900, "#{Time.now.inspect} => #{link[:expires_at]} = #{time_diff}s"
  end

  # At the moment, the Storage::LfsPolicy is used exclusively in the
  # Proxima multi-tenant environment, and does not construct valid URLs in
  # other environments.  Should that change, adjust these tests accordingly.
  test "download link", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @repo.network, state: 3
      link = Storage::LfsPolicy.new(blob).download_link
      assert_lfs_multi_tenant_link(link, @repo, blob, presigned: true)
      assert_s3_signed_lfs_link(link, presigned: true)
    end
  end

  test "download link with defined billing params including deploy key", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @owner, repository: @repo, key: @key).download_link
      assert_lfs_multi_tenant_link(link, @repo, blob, presigned: true)
      assert_s3_signed_lfs_link(link, presigned: true, actor_id: @owner.id, repo_id: @repo.id, key_id: @key.id)
    end
  end

  test "download link with defined billing params including customer ID", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @cust_repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @cust_owner, repository: @cust_repo).download_link
      assert_lfs_multi_tenant_link(link, @cust_repo, blob, presigned: true)
      refute @cust_repo.network_owner.delegate_billing_to_business?
      assert_s3_signed_lfs_link(link, presigned: true, actor_id: @cust_owner.id, repo_id: @cust_repo.id, cust_id: @customer.id)
    end
  end

  test "download link with defined billing params including business customer ID", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @org_repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @org_owner, repository: @org_repo).download_link
      assert_lfs_multi_tenant_link(link, @org_repo, blob, presigned: true)
      assert @org_repo.network_owner.delegate_billing_to_business?
      assert_s3_signed_lfs_link(link, presigned: true, actor_id: @org_owner.id, repo_id: @org_repo.id, cust_id: @business.customer.id, org_id: @business_org.id)
    end
  end

  test "upload link", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @repo.network, state: 3
      link = Storage::LfsPolicy.new(blob).lfs_upload_link
      assert_lfs_multi_tenant_link(link, @repo, blob)
      assert_s3_signed_lfs_link(link)
    end
  end

  test "upload link with defined billing params including deploy key", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @owner, repository: @repo, key: @key).lfs_upload_link
      assert_lfs_multi_tenant_link(link, @repo, blob)
      assert_s3_signed_lfs_link(link, actor_id: @owner.id, repo_id: @repo.id, key_id: @key.id)
    end
  end

  test "upload link with defined billing params including customer ID", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @cust_repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @cust_owner, repository: @cust_repo).lfs_upload_link
      assert_lfs_multi_tenant_link(link, @cust_repo, blob)
      refute @cust_repo.network_owner.delegate_billing_to_business?
      assert_s3_signed_lfs_link(link, actor_id: @cust_owner.id, repo_id: @cust_repo.id, cust_id: @customer.id)
    end
  end

  test "upload link with defined billing params including business customer ID", skip_enterprise: true do
    on_multi_tenant_enterprise do
      blob = create :media_blob, repository_network: @org_repo.network, state: 3
      link = Storage::LfsPolicy.new(blob, actor: @org_owner, repository: @org_repo).lfs_upload_link
      assert_lfs_multi_tenant_link(link, @org_repo, blob)
      assert @org_repo.network_owner.delegate_billing_to_business?
      assert_s3_signed_lfs_link(link, actor_id: @org_owner.id, repo_id: @org_repo.id, cust_id: @business.customer.id, org_id: @business_org.id)
    end
  end

  def assert_lfs_multi_tenant_link(link, repo, blob, presigned: false)
    expected = "^%s://%s/git-lfs/%d/%s\?" % [
      GitHub.lfs_storage_host_protocol,
      GitHub.lfs_storage_host,
      repo.network_id,
      blob.oid,
    ]
    expected += ".*X-Amz-Credential=#{GitHub.lfs_storage_account}" if presigned
    assert_match %r|#{expected}|, link[:href], link.inspect

    assert_match "Credential=#{GitHub.lfs_storage_account}", link[:header]["Authorization"], "Authorization has Credential" unless presigned
  end
end
