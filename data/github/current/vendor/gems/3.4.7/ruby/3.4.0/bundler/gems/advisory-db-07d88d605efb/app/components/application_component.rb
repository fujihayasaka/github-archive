# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  include ApplicationHelper

  # Function replicated from https://github.com/github/github/blob/3eed583dc6741a4f35365044c051032b1f3c3076/app/helpers/escape_helper.rb#L45-L49
  def safe_data_attributes(hash)
    hash.map do |key, value|
      "data-#{h(key.to_s.dasherize)}=\"#{h(value)}\""
    end.join(" ").html_safe # rubocop:disable Rails/OutputSafety
  end

  def disabled?
    defined?(@disabled) ? @disabled : false
  end

  def staging?
    ApplicationComponent.staging?
  end

  def self.staging?
    ENV["HEAVEN_DEPLOYED_ENV"] == "staging"
  end

  def self.primer_components_version
    @primer_components_version = JSON.parse(File.read("package.json"))["dependencies"]["@primer/view-components"] if @primer_components_version.blank?
    @primer_components_version
  end

  def self.primer_primitives_version
    @primer_primitives_version = JSON.parse(File.read("package.json"))["dependencies"]["@primer/primitives"] if @primer_primitives_version.blank?
    @primer_primitives_version
  end

  def self.primer_css_version
    @primer_css_version = JSON.parse(File.read("package.json"))["dependencies"]["@primer/css"] if @primer_css_version.blank?
    @primer_css_version
  end
end
