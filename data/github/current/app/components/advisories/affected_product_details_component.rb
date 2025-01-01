# typed: true
# frozen_string_literal: true

module Advisories
  class AffectedProductDetailsComponent < ApplicationComponent
    attr_reader :affected_product, :classes, :hide_affected_functions_column, :hide_headers, :show_suggest_link

    def initialize(affected_product:, classes: "", hide_headers: false, hide_affected_functions_column: true, show_suggest_link: false)
      @affected_product = affected_product
      @classes = classes
      @hide_headers = hide_headers
      @hide_affected_functions_column = hide_affected_functions_column
      @show_suggest_link = show_suggest_link
    end

    def affected_functions
      if affected_product[:affected_functions].size > 0
        affected_product[:affected_functions]
      else
        # for None
        [""]
      end
    end

    def affected_versions
      version_values_for(:affected_versions)
    end

    def class_for(value, text_bold: false)
      if value.present?
        "color-fg-default" + (text_bold ? " text-bold" : "")
      else
        "color-fg-muted"
      end
    end

    def ecosystem
      affected_product[:ecosystem].presence
    end

    def is_ecosystem_other?
      ecosystem == "other"
    end

    def normalized_ecosystem_name
      helpers.advisory_package_ecosystem(ecosystem)
    end

    def package
      affected_product[:package].presence
    end

    def package_label
      # note: for RepositoryAdvisory (repository_advisory_affected_products table),
      # an ecosystem with a custom name can be typed when the user picks Other
      # from the Ecosystem options. The value stored in the database column
      # `ecosystem` in that case would be the `custom-ecosystem-name`.
      # That is in contrast with Vulnerability (vulnerable_version_ranges table),
      # which might have an ecosystem value stored in the database that is
      # actually `other`, meaning it did not fit into any of our officially
      # supported ecosystems.
      if is_ecosystem_other?
        "Software"
      else
        "Package"
      end
    end

    def patched_versions
      version_values_for(:patched_versions)
    end

    def presented_package_value
      if package.present?
        package
      else
        "No package listed"
      end
    end

    def presented_value_for(value)
      if value.nil?
        "Unknown"
      elsif value == ""
        "None"
      else
        value
      end
    end

    def show_ecosystem?
      package.present? && ecosystem.present? && !is_ecosystem_other?
    end

    def show_ecosystem_icon_and_link?
      package.present? && normalized_ecosystem_name.present?
    end

    # nil means no version list was given.
    # "" (empty string) means packages were given, but version was blank.
    # other values mean a specific version.
    def version_values_for(field)
      if affected_product[field].blank?
        # for Unknown
        [nil]
      else
        affected_product_versions = affected_product[field].select(&:present?)

        if affected_product_versions.empty?
          # for None
          affected_product_versions.push("")
        end

        affected_product_versions
      end
    end
  end
end
