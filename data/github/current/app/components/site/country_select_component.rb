# typed: true
# frozen_string_literal: true

module Site
  class CountrySelectComponent < ApplicationComponent
    COUNTRY_LISTS = %w(default startups).freeze
    DEFAULT_COUNTRY_LIST = "default"

    def initialize(label:, name:, id:, required: true, country_list:, input_classes: "", label_classes: "", form_group_classes: "", include_blank: "Please select", selected: nil)
      @name = name
      @id = id
      @label = label
      @required = required
      @input_classes = input_classes
      @label_classes = label_classes
      @form_group_classes = form_group_classes

      @include_blank = include_blank
      @selected = selected

      @country_list = fetch_or_fallback(COUNTRY_LISTS, country_list, DEFAULT_COUNTRY_LIST)
    end

    private

    def input_class
      class_names(
        "input-block form-select error-border-transition js-validity-check",
        @input_classes,
        "required": @required
      )
    end

    def label_class
      class_names(
        "error-label-transition f5 text-bold",
        @label_classes,
        "required": @required
      )
    end

    def form_group_class
      class_names("form-group mb-0", @form_group_classes)
    end

    def countries(list_name)
      if list_name == "startups" || list_name == "default"
        ::TradeControls::Countries.marketing_targeted_countries.map { |(name, alpha2, _, _)| [name, alpha2] }
      end
    end
  end
end
