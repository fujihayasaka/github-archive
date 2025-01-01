
# typed: true
# frozen_string_literal: true

module Pages
  class VisibilitySelectItemComponent < ApplicationComponent
    include SvgHelper
    include PagesHelper
    include SettingsHelper

    attr_reader :repository, :current_selected

    def initialize(repository:, render_button:, current_selected:)
      @repository = repository
      @render_button = render_button
      @current_selected = current_selected
    end

    def name
      return "Public" if @render_button == :public
      return "Private" if @render_button == :private
    end

    def page
      @repository.page
    end

    def description
      return "Anyone on the internet can see this page." if @render_button == :public
      return "Only people with access to this repository can see this page." if @render_button == :private
    end

    def disable_items?

      if @repository.fork?
        return false if @repository.parent&.page&.private? && @render_button == :private
        return true if @repository.parent&.page&.private? && @render_button == :public
      end

      return false if @repository.org_members_can_create_both_pages?
      return !@repository.org_members_can_only_create_public_pages? if @render_button == :public
      return !@repository.org_members_can_only_create_private_pages? if @render_button == :private
    end

    def url_if_page_were_private
      subdomain = page.subdomain.nil? ? Page::Subdomain.new(repository: repository).for_dotcom_private : page.subdomain
      "https://#{subdomain}.pages.#{GitHub.pages_host_name_v2}"
    end
  end
end
