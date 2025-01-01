# typed: false
# frozen_string_literal: true

##
# While MetricQuery is the base, a strong majority of the metric queries
# are essentially a time series query of a single column from a single table.
# This module is a mixin that encapsulates the logic for this common scenario.
# It exposes class methods for defining the single model and column that
# comprises the query.
module MetricQuery::SingleModelColumn
  extend ActiveSupport::Concern

  included do
    class_attribute :model
    class_attribute :column, default: :created_at
    class_attribute :scopes, default: [ForRepoOwner, Bucketed]
  end

  private

  def fully_qualified_column
    "#{model.table_name}.#{column}"
  end

  # Exposes the relation from which the query will be based.
  # Starts with the model and mixes in additional helper methods to the scope.
  # https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html#method-i-extending
  def relation
    model.all.extending(*scopes)
  end
end
