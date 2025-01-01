# typed: true
# frozen_string_literal: true

class IssueTemplateConfig
  include UrlHelpers
  attr_reader :config, :repository

  def initialize(repository:, data:)
    @repository = repository
    @config = read_config(data)
  end

  # if blank_issues_enabled is neither true nor false, default to true
  def blank_issues_enabled?
    return false if config["blank_issues_enabled"] == false
    true
  end

  def configured?
    config.present?
  end

  def contact_links(issue_forms_only: false, viewer: nil)
    if issue_forms_only
      return build_issue_forms_contact_links(viewer: viewer)
    end

    results = []

    return results if config.empty?
    return results unless links = config["contact_links"]
    return results unless links.is_a?(Array)

    links.each_with_object(results) do |link, results|
      return results unless link.is_a?(Hash)
      contact_link = ContactLink.new(name: link["name"], about: link["about"], url: link["url"], repository: @repository)
      results << contact_link if contact_link.valid?
    end
  end

  class ContactLink
    include EscapeHelper
    attr_reader :name, :about, :repository, :url

    def initialize(name:, about:, url:, repository:)
      @name = name
      @about = about
      @url = url
      @repository = repository
    end

    def valid?
      name.present? && about.present? && url_valid?
    end

    def async_repository
      Promise.resolve(repository)
    end

    private

    def url_valid?
      safe_link = safe_uri(url)
      if safe_link
        uri = Addressable::URI.parse(url)
        UrlHelper.valid_host?(uri.host)
      else
        false
      end

    rescue Addressable::URI::InvalidURIError
      false
    end
  end

  private

  def read_config(data)
    return {} unless data
    begin
      loaded = YAML.safe_load(data) || {}
      config = loaded.is_a?(Hash) ? loaded : {}
    rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError => boom
      {}
    end
  end

  def build_issue_forms_contact_links(viewer: nil)
    templates = repository.issue_templates(viewer)&.valid_yaml_templates
    return [] unless templates

    templates.each_with_object([]) do |template, result|
      contact_link = ContactLink.new(name: template.name, about: template.about, url: build_issue_form_url(template), repository: @repository)
      result << contact_link if contact_link.valid?
    end
  end

  def build_issue_form_url(template)
    github_url = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"
    URI.join(github_url, new_issue_path(@repository.owner, @repository, params: { template: template.filename })).to_s
  end
end
