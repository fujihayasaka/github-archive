# typed: true
# frozen_string_literal: true

module PackageDependencies
  class IndexView < PackageDependencies::View
    include ActionView::Helpers::NumberHelper
    include PlatformHelper

    attr_reader :this_organization, :queries_for_sort_dropdown, :licenses, :selected_licenses

    def build_path(query: raw_query)
      if single_organization_scope?
        urls.packages_dashboard_org_insights_path(this_organization, query: query)
      else
        urls.packages_dashboard_path(query: query)
      end
    end

    def security_graph_path(query: raw_query)
      if single_organization_scope?
        urls.packages_dashboard_security_graph_org_insights_path(this_organization, query: query)
      else
        urls.packages_dashboard_security_graph_path(query: query)
      end
    end

    def licenses_graph_path(query: raw_query)
      if single_organization_scope?
        urls.packages_dashboard_licenses_graph_org_insights_path(this_organization, query: query)
      else
        urls.packages_dashboard_licenses_graph_path(query: query)
      end
    end

    def license_menu_content_path(query: raw_query)
      if single_organization_scope?
        urls.packages_dashboard_license_menu_content_org_insights_path(this_organization, query: query)
      else
        urls.packages_dashboard_license_menu_content_path(query: query)
      end
    end

    def organization_query
      if single_organization_scope?
        stringify_query([[:org, this_organization.display_login]])
      else
        build_query_with_only_qualifier(:org)
      end
    end

    def organization_filter_link?
      true
    end

    def single_organization_scope?
      this_organization.present?
    end

    def multi_organization_scope?
      !single_organization_scope?
    end

    def license_color(license_id)
      licenses.fetch(license_id, "#6C5FA0")
    end

    def license_label(license_id)
      license_id.gsub("-", " ")
    end

    def license_percentage(license_count, total_count)
      (license_count.to_f / total_count.to_f) * 100
    end

    def license_percentage_label(license_count, total_count)
      percentage = license_percentage(license_count, total_count)
      if percentage < 1
        "< 1%"
      else
        number_to_percentage(percentage, precision: 0)
      end
    end

    def top_licenses(licenses)
      if licenses.empty?
        return [{
          label: "Unknown",
          color: license_color("Unknown"),
          percent: 100,
          percent_label: "100%",
        }]
      end

      total_licenses_count = 0
      licenses.map { |license| total_licenses_count += license.total_count }

      # Filter out the Other grouping and add it back at the end with the rollup
      # of all license counts outside the top 6 most common
      licenses = licenses.reject { |license| license.license_id == "Other" }

      # Sort by total count and name
      licenses = licenses.sort_by(&:license_id).reverse.sort_by(&:total_count).reverse

      top_count = 0
      license_details = licenses.take(6).map do |license|
        top_count += license.total_count
        license_query = build_query(qualifier: :license, value: license.license_id, replace: true)
        {
          label: license_label(license.license_id),
          color: license_color(license.license_id),
          percent: license_percentage(license.total_count, total_licenses_count),
          percent_label: license_percentage_label(license.total_count, total_licenses_count),
          url:  build_path(query: license_query),
          selected: selected_license?(license),
        }
      end

      # Add rollup of other license counts
      other_count = total_licenses_count - top_count
      if other_count > 0
        license_details << {
          label: "Other",
          color: license_color("Other"),
          percent: license_percentage(other_count, total_licenses_count),
          percent_label: license_percentage_label(other_count, total_licenses_count),
        }
      end

      license_details
    end

    def selected_license?(license)
      selected_licenses.blank? || selected_licenses.include?(license.license_id)
    end
  end
end
