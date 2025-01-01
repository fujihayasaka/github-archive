# typed: strict
# frozen_string_literal: true

require "test_helper"
require "github/memory_dogstats_d"

class RepositorySidebarSectionVisibilityDependencyTest < GitHub::TestCase
  test "repositories default to visible" do
    repo = create(:repository)

    assert repo.sidebar_section_enabled?("packages")
  end

  test "hides sections" do
    repo = create(:repository)
    repo.update_sidebar_section_visibility({ "packages" => "0" }, actor: repo.owner)

    refute repo.sidebar_section_enabled?("packages")
  end

  test "gets current settings or nil" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    repo = create(:repository)

    expected_settings = {
      "packages" => "1",
      "releases" => "1",
      "environments" => "1",
      "deployments" => "1",
      "pages_url" => "1"
    }
    assert_equal expected_settings, repo.sidebar_sections_visibility

    settings = {
      "packages" => "1",
      "environments" => "1",
      "releases" => "0"
    }

    repo.update_sidebar_section_visibility(settings, actor: repo.owner)

    expected_settings = {
      "packages" => "1",
      "environments" => "1",
      "releases" => "0",
      "deployments" => "1",
      "pages_url" => "1"
    }

    assert_equal expected_settings, repo.sidebar_sections_visibility

    increment = GitHub.dogstats.increments("edit_repositories.hidden_sidebar_sections.count")[0]
    assert_equal 1, increment.value
    assert_includes increment.tags, "section:releases"
  end
end
