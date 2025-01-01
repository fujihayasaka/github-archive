# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"
require "github-launch"
require "test_helpers/launch/runner_groups_helper"

class ActionsRunnerApplicationsDependencyTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers
  include Actions
  include Api::Serializer::ActionsRunnersDependency

  fixtures do
    on_multi_tenant_enterprise do
      @owner = create :emu
      @business = @owner.enterprise_managed_business
      @org = create :organization, business: @business, admin: @owner
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "actions_org_runner_group_hash" do
    test "Runner Url is correct when listing runner groups" do
      runner_group = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
        id: 1,
        name: "Maze Runners",
        visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      )
      output = actions_org_runner_group_hash({ org: @org, runner_group: runner_group })
      assert_equal output[:runners_url], "https://api.#{@business.name}.github.com/orgs/#{@org.display_login}/actions/runner-groups/1/runners"
    end

  end
  context "actions_runner_applications_hash" do
    test "Runner Download works for non-air gapped runners" do
      runners = [
        { os: "linux", architecture: "x64", download_url: "https://something.com/linux.tar.gz", filename: "linux.tar.gz" },
        { os: "linux", architecture: "arm32", download_url: "https://something.com/linux.arm32.tar.gz", filename: "linux.arm32.tar.gz" },
        { os: "win", architecture: "x64", download_url: "https://something.com/win.tar.gz", filename: "win.tar.gz" },
        { os: "osx", architecture: "x64", download_url: "https://something.com/osx.tar.gz", filename: "osx.tar.gz" },
      ]
      resp = GitHub::Launch::Services::Selfhostedrunners::ListDownloadsResponse.new(
        downloads: runners.map do |download|
          GitHub::Launch::Services::Selfhostedrunners::Download.new(
            type: "agent",
            os: download[:os],
            architecture: download[:architecture],
            download_url: download[:download_url],
            filename: download[:filename],
          )
        end,
      )
      output = actions_runner_applications({ downloads: resp.downloads })

      output.each_with_index do |response_download, index|
        assert_equal runners[index][:os], response_download["os"]
        assert_equal runners[index][:architecture], response_download["architecture"]
        assert_equal runners[index][:download_url], response_download["download_url"]
        assert_equal runners[index][:filename], response_download["filename"]
        assert_equal false, response_download.key?("sha256_checksum")
        assert_equal false, response_download.key?("temp_download_token")
      end
    end

    test "sets sha256_checksum and temp_download_token for air gapped runners" do
      runners = [
        { os: "linux", architecture: "x64", download_url: "https://something.com/linux.tar.gz", filename: "linux.tar.gz", sha256_hash: "7215c75a462eeb6a839fa8ed298d79f620617d44d47d37c583114fc3f3b27b30", download_token: "fake_token" },
        { os: "linux", architecture: "arm32", download_url: "https://something.com/linux.arm32.tar.gz", filename: "linux.arm32.tar.gz", sha256_hash: "f1fa173889dc9036cd529417e652e1729e5a3f4d35ec0151806d7480fda6b89b", download_token: "fake_token" },
        { os: "win", architecture: "x64", download_url: "https://something.com/win.tar.gz", filename: "win.tar.gz", sha256_hash: "02d710fc9e0008e641274bb7da7fde61f7c9aa1cbb541a2990d3450cc88f4e98", download_token: "fake_token" },
        { os: "osx", architecture: "x64", download_url: "https://something.com/osx.tar.gz", filename: "osx.tar.gz", sha256_hash: "a6aa6dd0ba217118ef2b4ea24e9e0a85b02b13c38052a5de0776d6ced3a79c64", download_token: "fake_token" },
      ]
      resp = GitHub::Launch::Services::Selfhostedrunners::ListDownloadsResponse.new(
        downloads: runners.map do |download|
          GitHub::Launch::Services::Selfhostedrunners::Download.new(
            type: "agent",
            os: download[:os],
            architecture: download[:architecture],
            download_url: download[:download_url],
            filename: download[:filename],
            sha256_hash: download[:sha256_hash],
            download_token: download[:download_token],
          )
        end,
      )
      output = actions_runner_applications({ downloads: resp.downloads })

      output.each_with_index do |response_download, index|
        assert_equal runners[index][:os], response_download["os"]
        assert_equal runners[index][:architecture], response_download["architecture"]
        assert_equal runners[index][:download_url], response_download["download_url"]
        assert_equal runners[index][:filename], response_download["filename"]
        assert_equal runners[index][:sha256_hash], response_download["sha256_checksum"]
        assert_equal runners[index][:download_token], response_download["temp_download_token"]
      end
    end
  end
end
