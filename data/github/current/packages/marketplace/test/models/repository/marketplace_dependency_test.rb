# typed: true
# frozen_string_literal: true

require "test_helper"

class MobileAppDetectionTest < GitHub::TestCase
  include Marketplace::Domain::Provider

  fixtures do
    @repo = create :repository, from_example: :mobile_app
  end

  %w(android ios react xamarin swift).each do |framework|
    test "finds #{framework} apps" do
      marketplace_domain.repository_settings.clear_mobile_status(@repo.id)
      @repo.update_default_branch("#{framework}")

      assert_equal "1", marketplace_domain.repository_settings.set_mobile_status(@repo)
      assert marketplace_domain.repository_settings.is_mobile?(@repo.id)
    end
  end

  test "returns/stores negative results for non-mobile apps" do
    marketplace_domain.repository_settings.clear_mobile_status(@repo.id)
    @repo.update_default_branch("master")

    assert_equal "0", marketplace_domain.repository_settings.set_mobile_status(@repo)
    refute marketplace_domain.repository_settings.is_mobile?(@repo.id)
  end
end

class DockerfileDetectionTest < GitHub::TestCase
  include Marketplace::Domain::Provider

  fixtures do
    @docker_repo = create :repository, from_example: :dockerfile
  end

  test "identifies repositories with a Dockerfile" do
    marketplace_domain.repository_settings.clear_docker_file_status(@docker_repo.id)
    @docker_repo.update_default_branch("master")

    assert_equal "1", marketplace_domain.repository_settings.set_docker_file_status(@docker_repo)
    assert marketplace_domain.repository_settings.has_docker_file?(@docker_repo.id)
  end

  test "does not identify repositories with a Dockerfile in a sub directory" do
    marketplace_domain.repository_settings.clear_docker_file_status(@docker_repo.id)
    @docker_repo.update_default_branch("sub_dir")

    assert_equal "0", marketplace_domain.repository_settings.set_docker_file_status(@docker_repo)
    refute marketplace_domain.repository_settings.has_docker_file?(@docker_repo.id)
  end

  test "returns/stores negative results for repositories without a Dockerfile" do
    marketplace_domain.repository_settings.clear_docker_file_status(@docker_repo.id)
    @docker_repo.update_default_branch("no_docker_file")

    assert_equal "0", marketplace_domain.repository_settings.set_docker_file_status(@docker_repo)
    refute marketplace_domain.repository_settings.has_docker_file?(@docker_repo.id)
  end
end
