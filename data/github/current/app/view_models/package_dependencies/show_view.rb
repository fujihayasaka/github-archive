# typed: true
# frozen_string_literal: true

module PackageDependencies
  class ShowView < PackageDependencies::View
    include PlatformHelper

    attr_reader :selected_tab, :package_manager, :package_name, :package_version, :repository, :dependent_search

    def build_path(query: raw_query, tab: selected_tab)
      urls.package_details_path(
        query: query,
        tab: tab,
        name: ERB::Util.url_encode(package_name),
        ecosystem: package_manager,
        version: ERB::Util.url_encode(package_version),
        dependent_name: dependent_search,
      )
    end

    def tab_selected?(tab)
      selected_tab == tab
    end

    def organization_filter_link?
      false
    end

    def render_advisory_description(description, id)
      GitHub::Goomba::MarkdownPipeline.to_html(description)
    rescue EncodingError, TypeError => error
      Failbot.report(error, "gh.ghsa_id" => id, "gh.global_advisory.description" => description)
      nil
    end
  end
end
