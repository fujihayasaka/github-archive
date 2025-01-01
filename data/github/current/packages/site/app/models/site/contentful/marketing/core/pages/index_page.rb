# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Core::Pages::IndexPage < Site::Contentful::Marketing::ContainerPage
  extend T::Helpers
  include Site::Contentful::Marketing::Core::Pages::CardSorting

  PageSettingsType = T.type_alias do
    T::Hash[Symbol, T.any(T.nilable(String), T.nilable(T::Boolean))]
  end

  sig do
    params(
      path: String,
      url: String,
      locale: String,
      query: T::Hash[Symbol, T.untyped],
      per_page: T.nilable(Integer),
      preview: T::Boolean,
    ).void
  end
  def initialize(path:, url:, locale:, query:, per_page: nil, preview: false)
    super(path:, url:, locale:, preview:)
    @query = T.let(query, T::Hash[Symbol, T.untyped])
    @page_number = T.let((query[:page] || 1).to_i, Integer)
    @per_page = T.let(per_page || 12, Integer)
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.index.#{@path}.#{@locale}/v3"
  end

  sig { override.params(new_data: JsonLikeType).void }
  def validate!(new_data)
    traverser = Site::Contentful::Swp::Page::Traverser.new(new_data)

    JSON::Validator.validate!(Site::Contentful::Swp::Schemas::Page.build, traverser.fields)
    JSON::Validator.validate!(Site::Contentful::Marketing::Core::Schemas::IndexTemplate.build, traverser.get_field("template"))
  end

  sig { returns(String) }
  def title
    base_title = super
    return "" if base_title.blank?

    base_title += " - Page #{@page_number}" if @page_number > 1
    base_title
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def refined_view_data
    contentful_data = view_data.deep_dup

    template_entry = contentful_data.dig("includes", "Entry")&.find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "templateIndex"
    end

    if template_entry
      template_entry["fields"]["cards"] = cards
    end

    contentful_data
  end


  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def grouped_filters
    return [] if template.blank?

    # Extract the filter link IDs in order
    filter_ids_in_order = (template.dig("fields", "filters") || []).map { |link| link.dig("sys", "id") }

    # Build a lookup hash of filter entries
    filter_entries_by_id = included_entries.each_with_object({}) do |entry, hash|
      if entry.dig("sys", "contentType", "sys", "id") == "indexFilter"
        hash[entry.dig("sys", "id")] = entry
      end
    end

    # Group filters preserving order
    groups = {}
    group_order = []

    filter_ids_in_order.each do |filter_id|
      entry = filter_entries_by_id[filter_id]
      next if entry.blank?

      fields = entry["fields"]
      next if fields.blank?

      group_value = fields["groupValue"]
      group_label = fields["groupName"]
      filter_value = fields["filterValue"]

      next if group_value.blank? || group_label.blank?

      # Initialize group if needed
      groups[group_value] ||= {
        value: group_value,
        label: group_label,
        checkboxes: []
      }

      group_order << group_value unless group_order.include?(group_value)

      checkbox = {
        label: fields["filterName"],
        value: filter_value,
        isChecked: checkbox_selected?(group_value, filter_value)
      }

      groups[group_value][:checkboxes] << checkbox
    end

    group_order.map { |group_value| groups[group_value] }
  end

  sig { returns(T::Array[CardType]) }
  def cards
    start_index = (@page_number - 1) * @per_page
    cards_unpaginated[start_index, @per_page] || []
  end

  sig { returns(Integer) }
  def total_pages
    (filtered_cards_count.to_f / @per_page).ceil
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def sort_options_with_values
    sort_options = template.dig("fields", "sortOptions") || []
    sort_options.map do |label|
      symbol_value = SORT_OPTION_MAP[label]
      value = symbol_value.to_s if symbol_value # convert symbol to string for FE/query param
      { label: label, value: value } if value
    end.compact
  end

  sig { returns(Symbol) }
  def current_sort_value
    sort_options = template.dig("fields", "sortOptions") || []
    default_sort = template.dig("fields", "defaultSort") || "Newest"
    mapped_options = sort_options.map { |label| SORT_OPTION_MAP[label] }.compact
    mapped_default = SORT_OPTION_MAP[default_sort] || :date_desc
    param = @query[:sort]&.to_sym

    if mapped_options.empty?
      mapped_default
    elsif mapped_options.size == 1
      mapped_options.first
    elsif mapped_options.include?(param)
      param
    elsif mapped_options.include?(mapped_default)
      mapped_default
    else
      mapped_options.first
    end
  end

  sig { returns(T::Boolean) }
  def show_spotlight_card
    # If any filter or sort is applied (even if it's the default), or if the user is not on the first page,
    # the spotlight card will not display.
    spotlight_card = template.dig("fields", "spotlightCard")
    filter_keys = grouped_filters.map { |group| group[:value].to_sym }
    has_filter = filter_keys.any? { |key| @query[key].present? }

    return false unless spotlight_card.present? &&
                        @page_number == 1 &&
                        @query[:sort].blank? &&
                        !has_filter

    true
  end

  private

  sig { params(group_value: String, filter_value: String).returns(T::Boolean) }
  def checkbox_selected?(group_value, filter_value)
    param_values = @query[T.unsafe(group_value).to_sym]
    return false if param_values.blank?

    Array(param_values).flat_map { |v| v.to_s.split(",") }.include?(filter_value)
  end

  sig { params(filter_value: String).returns(T.nilable(String)) }
  def filter_id_for(filter_value)
    entries = view_data.dig("includes", "Entry") || []

    filter_entry = entries.find do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "indexFilter" &&
        entry.dig("fields", "filterValue") == filter_value
    end

    filter_entry&.dig("sys", "id")
  end

  sig { returns(Integer) }
  def filtered_cards_count
    cards_unpaginated.length
  end

  sig { returns(T::Array[Site::Contentful::Marketing::Core::Pages::CardSorting::CardType]) }
  def cards_unpaginated
    return [] if template.blank?

    linked_card_ids = template.dig("fields", "cards")&.map { |link| link.dig("sys", "id") } || []

    all_cards = included_entries.select do |entry|
      entry.dig("sys", "contentType", "sys", "id") == "indexCard" &&
        linked_card_ids.include?(entry.dig("sys", "id"))
    end

    filtered = all_cards.select do |card|
      card_filters = card.dig("fields", "indexFilters") || []
      card_filter_ids = card_filters.map { |f| f.dig("sys", "id") }

      grouped_filters.all? do |group|
        selected_values = @query[group[:value].to_sym]
        next true if selected_values.blank?

        selected_values = Array(selected_values).flat_map { |v| v.split(",") }

        group[:checkboxes].any? do |checkbox|
          selected_values.include?(checkbox[:value]) && card_filter_ids.include?(filter_id_for(checkbox[:value]))
        end
      end
    end

    if show_spotlight_card
      spotlight_id = template.dig("fields", "spotlightCard", "sys", "id")
      filtered = filtered.reject { |card| card.dig("sys", "id") == spotlight_id }
    end

    public_send(current_sort_value, filtered) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def serialize
    super.merge({ query: @query, per_page: @per_page })
  end
end
