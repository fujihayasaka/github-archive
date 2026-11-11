# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::DeveloperOptionsComponent < ApplicationComponent
  def initialize(form:, repo:, vscs_target_options:, selected_target_name: nil, vscs_target_url: nil)
    @form, @repo, @vscs_target_options = form, repo, vscs_target_options
    @selected_target_name = selected_target_name || vscs_target_name(Codespaces::Vscs.default_target_config)
    @vscs_target_url = vscs_target_url
  end

  def render?
    developer_options?
  end

  # returns symbol
  def vscs_target_name(target)
    target&.dig(:name)
  end

  def vscs_target_display_name(target)
    target&.dig(:display_name)
  end

  def local_target?(target)
    vscs_target_name(target) == :local
  end

  def selected_vscs_target?(target)
    vscs_target_name(target) == selected_target_name.to_sym
  end

  def default_target?(target)
    vscs_target_name(target) == vscs_target_name(Codespaces::Vscs.default_target_config)
  end

  def geos_by_vscs_target(vscs_target)
    Codespaces::Locations::Geo.where(vscs_target:).map(&:id)
  end

  private

  def developer_options?
    vscs_target_options.any?
  end

  attr_reader :form, :repo, :vscs_target_options, :selected_target_name,  :vscs_target_url
end
