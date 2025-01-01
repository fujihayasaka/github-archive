# typed: true
# frozen_string_literal: true

require "test_helper"

class PageDeploymentTest < GitHub::TestCase
  include PageHelper

  fixtures do
    @page = create :page
    @owner = @page.owner
    @repo = @page.repository

    @preview_deployment = ::Page::Deployment.create!(page_id: @page.id, ref_name: "branch-build")
    @main_deployment = ::Page::Deployment.create!(page_id: @page.id, ref_name: @page.source_branch)

    @deployment_without_a_page = ::Page::Deployment.create!(page_id: @page.id, ref_name: "trololololol")
    @deployment_without_a_page.update_column :page_id, 0

    deploy_page(@page, git_ref_name: "branch-build")
    deploy_page(@page, git_ref_name: @page.source_branch)
  end

  test "it sets a token automatically" do
    assert_match %r!^[a-f0-9]{10}$!, @preview_deployment.token
    assert_match %r!^[a-f0-9]{10}$!, @main_deployment.token
  end

  test "it doesn't reset the token if it's already given" do
    deployment = Page::Deployment.create!(page_id: @page.id, ref_name: "another-ref", token: "atoken")
    deployment.save!
    assert_equal "atoken", deployment.token
  end

  test "determines if branch_build?" do
    assert @preview_deployment.branch_build?, "This ref_name should indicate a branch build."
    refute @main_deployment.branch_build?, "This ref_name should indicate a main build."
  end

  test "knows its url" do
    assert_equal @page.url.to_s, @main_deployment.url
    assert_equal @preview_deployment.preview_url, @preview_deployment.url
  end

  test "knows its preview_url" do
    url = Addressable::URI.new(
      scheme: @page.url.scheme,
      host: "#{@owner.login}-#{@preview_deployment.token}.#{GitHub.pages_preview_hostname}",
      path: "/#{@repo.name}/",
    )
    assert_equal url.to_s, @preview_deployment.preview_url
  end

  test "deletes the deployment if the ref is destroyed" do
    refute_nil Page::Deployment.find_by(id: @preview_deployment.id)
    assert Page::Replica.where(pages_deployment_id: @preview_deployment.id).exists?
    @repo.ref_deleted("refs/heads/#{@preview_deployment.ref_name}")
    @repo.handle_pages_branch_delete("refs/heads/#{@preview_deployment.ref_name}")
    @repo.handle_pages_deployments_delete("refs/heads/#{@preview_deployment.ref_name}")
    assert_nil Page::Deployment.find_by(id: @preview_deployment.id)
    refute Page::Replica.where(pages_deployment_id: @preview_deployment.id).exists?
  end

  test "knows its source directory" do
    assert_equal "/", @main_deployment.async_source_directory.sync
    assert_equal "/", @preview_deployment.async_source_directory.sync
  end

  test "source directory lookup handles nil page" do
    assert_nil @deployment_without_a_page.async_source_directory.sync
  end

  test "knows if it's the primary deployment" do
    assert @main_deployment.async_primary_deployment?.sync
    refute @preview_deployment.async_primary_deployment?.sync
  end

  test "return nil when looking up primary deployment without a page record" do
    assert_nil @deployment_without_a_page.async_primary_deployment?.sync
  end

  test "workflow type pages deployment not throw" do
    @page.update(build_type: "workflow")
    assert_nothing_raised { @preview_deployment.async_primary_deployment?.sync }
  end
end
