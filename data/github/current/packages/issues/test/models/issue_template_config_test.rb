# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTemplateConfigTest < GitHub::TestCase
  setup do
    @repo = create :repository
  end

  context "#blank_issues_enabled?" do
    test "returns true if blank_issues_enabled is true" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled: true")
      assert config.blank_issues_enabled?
    end

    test "returns false if blank_issues_enabled is false" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled: false")
      refute config.blank_issues_enabled?
    end

    test "returns true if blank" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled")
      assert config.blank_issues_enabled?
    end

    test "returns true by default" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled: hello")
      assert config.blank_issues_enabled?
    end
  end

  context "#configured?" do
    test "returns true if config is present" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled: false")
      assert config.configured?
    end

    test "returns false if config is empty" do
      config = IssueTemplateConfig.new(repository: @repo, data: nil)
      refute config.configured?
    end
  end

  context "#contact_links" do
    test "returns an empty array if config is empty" do
      config = IssueTemplateConfig.new(repository: @repo, data: nil)
      assert_empty config.contact_links
    end

    test "returns an empty array if contact_links is missing from config.yml" do
      config = IssueTemplateConfig.new(repository: @repo, data: "blank_issues_enabled: true")
      assert_empty config.contact_links
    end

    test "creates and returns an array of ContactLinks" do
      contact_links = {
        "contact_links" => [
          {
            "name" => "IRC",
            "url" => "http://example.com",
            "about" => "Chat",
          },
          {
            "name" => "Slack",
            "url" => "https://slack.com",
            "about" => "Chat elsewhere",
          },
        ],
      }.to_yaml

      config = IssueTemplateConfig.new(repository: @repo, data: contact_links)
      assert_equal 2, config.contact_links.size

      result = config.contact_links.first
      assert_includes contact_links, result.name
      assert_includes contact_links, result.about
      assert_includes contact_links, result.url
    end

    test "omits invalid contact links" do
      contact_links = {
        "contact_links" => [
          {
            "name" => "fake news",
            "url" => "bogus",
            "about" => "not gonna show up",
          },
          {
            "name" => "fake news",
            "url" => "http://example.com<script>",
            "about" => "not gonna show up",
          },
        ],
      }.to_yaml

      config = IssueTemplateConfig.new(repository: @repo, data: contact_links)
      assert_equal 0, config.contact_links.size
    end

    test "returns an empty array if contact_links is not an array of hashes" do
      contact_links = {
        "contact_links" => [
          [
            "name" => "fake news",
            "url" => "bogus",
            "about" => "not gonna show up",
          ],
        ],
      }.to_yaml

      config = IssueTemplateConfig.new(repository: @repo, data: contact_links)
      assert_equal 0, config.contact_links.size
    end

    test "returns an empty array if contact_links is not an array" do
      contact_links = {
        "contact_links" => "this file is broken",
      }.to_yaml

      config = IssueTemplateConfig.new(repository: @repo, data: contact_links)
      assert_equal 0, config.contact_links.size
    end

    test "does not raise when config.yml is empty" do
      config = IssueTemplateConfig.new(repository: @repo, data: nil)
      assert_empty config.contact_links
    end
  end

  context "invalid yaml" do
    test "gracefully handles yaml that is an array of values" do
      data = "- name: API\n    url: https://foo.bar/\n    about: Report bugs or suggest features for the API.\n"
      config = IssueTemplateConfig.new(repository: @repo, data: data)
      assert_equal 0, config.contact_links.size
      assert_empty config.contact_links
    end
  end
end
