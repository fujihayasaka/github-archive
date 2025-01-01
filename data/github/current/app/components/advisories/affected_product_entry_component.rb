# typed: true
# frozen_string_literal: true

module Advisories
  class AffectedProductEntryComponent < ApplicationComponent
    attr_reader :classes, :form, :index, :row_index

    # form: an instance of a form builder that is tied to a specific model that
    #   represents the affected product.
    #
    # field_mappings is a hash that can be used to override the default property
    #   names appended to the name attribute of each field. This is useful when the
    #   underlying model that contains affected product data has different property
    #   names than the ones used in the template. For example:
    #     the name attribute "repository_advisory[package]" can be turned
    #     into "repository_advisory[affects]" when you specify
    #     field_mappings: { package: :affects }
    #   With that, data from existing records will also populate the fields
    #   correctly without erroring out.
    #
    # index: specifies the index for each individual field. Use this when you
    # are working with multiple records, but the form.object_name does not
    # already include the index. Otherwise, keep it as nil.
    def initialize(classes: "", field_mappings: {}, form:, index: nil, show_delete_button:, include_destroy_input:, include_ecosystem_other:, require_ecosystem: true, innersource: false, test_selector_value: nil, row_index: nil)
      @classes = classes
      @field_mappings = field_mappings
      @form = form
      @index = index
      @show_delete_button = show_delete_button
      @include_destroy_input = include_destroy_input
      @include_ecosystem_other = include_ecosystem_other
      @test_selector_value = test_selector_value
      # When require_ecosystem is nil, we want the default to be true.
      @require_ecosystem = require_ecosystem == false ? false : true
      @innersource = innersource
      @row_index = row_index || index
    end

    def affected_product
      form.object
    end

    def affected_versions_field
      field_mappings[:affected_versions] || :affected_versions
    end

    def ecosystem_id
      form.field_id(:ecosystem, index: index)
    end

    def ecosystem_label_id
      form.field_id(:ecosystem_label, index: index)
    end

    def ecosystem_other_field_name
      infix = "[#{index}]" if index
      "#{form.object_name}#{infix}[ecosystem_other]"
    end

    def ecosystem_other_hidden
      ecosystem_selected != "other"
    end

    def ecosystem_other_value
      ecosystem_other_hidden ? "" : affected_product.ecosystem
    end

    def ecosystem_selected
      # A known ecosystem whose value appears as an option in the select can
      # be mapped directly from the ecosystem property of an affected_product.
      # But for all other cases, we have to determine whether to automatically
      # pick the "other" option or to prompt the user to choose one.
      #
      # Example cases for ecosystem value:
      #
      #   "" (empty string) - special case where at some point in the past users
      #     were able to save with an empty string. Maps to the "other" option.
      #   "whatever" - a custom name for the ecosystem defaults to the "other" option.
      #   "maven" - a known ecosystem name maps directly to the corresponding option.
      #   nil - record does not yet exist, prompting the user to choose an ecosystem.
      if affected_product.ecosystem && (affected_product.ecosystem.empty? || ::AdvisoryDB::Ecosystems.public_names.exclude?(affected_product.ecosystem))
        return "other"
      end

      affected_product.ecosystem
    end

    def ecosystem_selection_options
      ecosystem_names = ::AdvisoryDB::Ecosystems.public_names

      if include_ecosystem_other?
        # Temporary mitigation fix to the bug where users no longer have the option
        # to type a custom ecosystem (Option "Other" is missing from dropdown because
        # OTHER in PUBLIC_NAMES was made no longer public)
        # See https://github.com/github/team-advisory-database/issues/2070
        ecosystem_names = ecosystem_names + ["other"]
      end

      ecosystem_names.map do |ecosystem_name|
        [::AdvisoryDB::Ecosystems.label(ecosystem_name), ecosystem_name]
      end
    end

    def include_destroy_input?
      @include_destroy_input
    end

    def include_ecosystem_other?
      @include_ecosystem_other
    end

    def package_field
      field_mappings[:package] || :package
    end

    def patches_field
      field_mappings[:patches] || :patches
    end

    def show_delete_button?
      @show_delete_button
    end

    def require_ecosystem?
      @require_ecosystem
    end

    def innersource?
      @innersource
    end

    memoize def test_selector_value
      field_id = form.field_id("", index: index)
      # if the form.object_name already includes an index, we have to remove
      # the underscore at the end that gets added preceding an empty method name.
      @test_selector_value || if field_id[-1] == "_"
                                field_id[0...-1]
                              else
                                field_id
                              end
    end

    private

    attr_reader :field_mappings
  end
end
