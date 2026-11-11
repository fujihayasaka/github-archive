# typed: true
# frozen_string_literal: true

class Businesses::Admins::IndexView < Businesses::QueryView
  # query filters defined for QueryView
  attr_reader :role, :account_type, :organizations, :two_factor_status, :sort

  def filter_map
    BusinessesHelper::ADMINS_QUERY_FILTERS
  end
end
