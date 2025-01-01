# typed: true
# frozen_string_literal: true

class Businesses::UserNamespaceRepositoriesView < Businesses::QueryView
  attr_reader :business, :status, :sort

  def initialize(**args)
    super(args)
  end

  def filter_map
    BusinessesHelper::USER_NAMESPACE_REPOSITORY_FILTER
  end
end
