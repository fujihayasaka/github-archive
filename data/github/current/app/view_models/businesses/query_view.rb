# typed: true
# frozen_string_literal: true

# Defines generic logic for query filter handling.
# Classes inheriting from this view model should override `#filter_map` and
# define attribute accessors for each filter
class Businesses::QueryView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include BusinessesHelper

  attr_reader :query, :original_query

  def after_initialize
    @original_query = @query

    # parse out any filters from the query string and update this viewmodel
    # with the values
    update parse_query_string(query, filter_map: filter_map)
  end

  def apply_query_filters(filters = {})
    filters = default_filters.merge(filters)

    filters = filters
      .reject { |_k, v| v.blank? }
      .map do |k, v|
        if v.is_a?(Array)
          query_filter_string_from_array(k, v)
        else
          "#{k}:#{v}"
        end
      end

    "#{query} #{filters.join(" ")}".strip
  end

  # Returns a hash of filter data used in a view model, for the corresponding view.
  # This should be overridden in classes that inherit from QueryView.
  # The format of this hash should look like
  # {
  #   # name of the filter, as expected to be shown in the UI
  #   name => {
  #     # filter regex pattern
  #     filter: /\bname:(\S+)/,
  #
  #     # does the filter match multiple values
  #     multi: false,
  #
  #     # (optional) a corresponding GraphQL enum value, if needed
  #     graphql_enum: Platform::Enums::EnterpriseUserAccountMembershipRole
  #   }
  # }
  #
  # See app/helpers/businesses_helper.rb, BusinessesHelper.MEMBERS_QUERY_FILTERS
  # for an example
  def filter_map
    {}
  end

  # Returns the current filter values for the view model as a hash, with filters
  # obtained by matching `#filter_map` keys to current values set for those keys
  def default_filters
    filter_map.keys.map { |k| { k => self.send(k) } }.reduce({}, &:merge)
  end

  def query_or_filters_present?
    original_query.to_s.strip.present?
  end

  private

  def query_filter_string_from_array(key, array)
    # If key is :organizations, each filter in the resulting string should
    # be "organization:<login>".
    filter_key = key.to_s.singularize
    array
      .delete_if { |item| item.blank? }
      .map { |item| "#{filter_key}:#{item}" }.join(" ")
  end
end
