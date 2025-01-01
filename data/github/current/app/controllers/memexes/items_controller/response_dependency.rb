# typed: strict
# frozen_string_literal: true

module Memexes::ItemsController::ResponseDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  include GitHub::Memoizer
  include MemexesHelper
  include Memexes::MemexProjectItemDependency
  include Memexes::ThisRepositoryDependency

  requires_ancestor { Memexes::Controller }

  NEWLINE_REGEX = T.let(Regexp.union(["\r\n", "\r", "\n"]), Regexp)

  private

  sig { returns(T::Array[Symbol]) }
  def memex_create_column_params
    column_values = underscored_params.dig(:memex_project_item, :memex_project_column_values) || []
    [:memex_project_column_id] + column_values.map { |param| value_param_type_value(param) }
  end

  sig { returns(T::Array[Symbol]) }
  def memex_update_column_params
    column_values = underscored_params.dig(:memex_project_column_values) || []
    [:memex_project_column_id, :append_only] + column_values.map { |param| value_param_type_value(param) }
  end

  # These are similar to value_param_type_value, but attempts to coerce multiple (list of) values
  # of different shapes into something that strong_params will not throw on.
  sig { returns(T::Array[Symbol]) }
  def memex_bulk_update_column_params
    first_item_or_empty = underscored_params[:memex_project_items]&.first || {}
    column_values = first_item_or_empty[:memex_project_column_values] || []
    [:memex_project_column_id] + column_values.map { |param| value_param_type_value(param) }
  end

  sig { returns(ActionController::Parameters) }
  def create_memex_item_params
    underscored_params.require(:memex_project_item).permit(
      :content_type,
      :previous_memex_project_item_id,
      content: [:title, :id, :repository_id],
      memex_project_column_values: memex_create_column_params
    )
  end

  sig { returns(T.nilable(T.any(Issue, PullRequest))) }
  memoize def this_content
    return unless this_repository
    find_content(
      repository: T.must(this_repository),
      content_type: create_memex_item_params[:content_type],
      content_id: create_memex_item_params[:content][:id],
    )
  end

  sig { void }
  def require_this_content
    return if create_memex_item_params[:content_type] == DraftIssue.name
    render_404 unless this_content&.readable_by?(current_user)
  end

  sig { void }
  def require_valid_content_parameters
    verify_content_params(create_memex_item_params)
  end

  # This method is used to validate the parameters for single/bulk item actions. This validation specifically uses
  # `underscored_params` to access the parameters, as it contains the original parameter names. The reason we can't use
  # the more specific methods like `single_item_update_params` is because the behavior of `.permit` is different when
  # running in production vs. development/test environments and would require a larger refactor to support.
  # See: config/environments/production.rb vs. config/environments/development.rb
  sig { void }
  def require_valid_project_item_params
    head :bad_request if underscored_params[:memex_project_items] && underscored_params[:memex_project_item_id]
  end

  sig { void }
  def require_this_repository_for_non_draft_issue
    return if create_memex_item_params[:content_type] == DraftIssue.name
    require_this_repository
  end

  sig { returns(T::Array[ActionController::Parameters]) }
  def create_multiple_column_value_params
    create_memex_item_params[:memex_project_column_values] || []
  end

  sig { returns(T::Array[T::Hash[Symbol, MemexProjectColumn]]) }
  memoize def column_list_for_item_creation
    create_multiple_column_value_params.reduce([]) do |column_data_acc, column_value_params|
      column_id = column_value_params[:memex_project_column_id]
      column = this_memex.find_column_by_name_or_id(column_id)

      if column
        column_data_acc.push({ column: column, value: column_value_params[:value] })
      else
        column_data_acc
      end
    end
  end

  sig { returns(T::Array[T.nilable(Symbol)]) }
  memoize def column_types_to_update
    column_list_for_item_update.map { |c| c[:column]&.data_type&.to_sym }
  end

  sig { void }
  def require_valid_update_for_draft_issue
    invalid_columns = [:labels, :milestone]
    if invalid_columns.intersect?(column_types_to_update)
      column_list = invalid_columns.intersection(column_types_to_update).join(",")
      error = "Cannot update column #{column_list} for a draft issue"
      render_json_error(error: error, status: :unprocessable_entity)
    end
  end

  sig { void }
  def require_actor_can_update_title
    require_these_items_editable if column_types_to_update.include?(:title)
  end

  sig { void }
  def require_repository_has_issues
    require_these_items_have_issues_enabled if [:assignees, :labels, :milestone].intersect?(column_types_to_update)
  end

  sig { returns(T::Array[T::Hash[Symbol, MemexProjectColumn]]) }
  memoize def column_list_for_item_update
    return [] unless update_multiple_column_value_params
    T.must(update_multiple_column_value_params).reduce([]) do |column_data_acc, column_value_params|
      column_id = column_value_params[:memex_project_column_id]
      column = this_memex.find_column_by_name_or_id(column_id)

      if column
        column_data_acc.push({ column: column, value: column_value_params[:value],
          append_only: column_value_params[:append_only] })
      else
        column_data_acc
      end
    end
  end

  sig { returns(T.nilable(T::Array[ActionController::Parameters])) }
  memoize def update_multiple_column_value_params
    if single_item_update_request?
      single_item_update_params[:memex_project_column_values] || []
    elsif bulk_item_update_request?
      first_item_or_default = bulk_item_update_params[:memex_project_items]&.first || {}
      first_item_or_default[:memex_project_column_values] || []
    end
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.any(Symbol, String)])) }
  def validate_item_update_with_multiple_columns
    if update_multiple_column_value_params
      if T.must(update_multiple_column_value_params).length > MemexProject::COLUMN_LIMIT
        return {
          error: "You have exceeded the maximum column values for this request",
          status: :unprocessable_entity,
        }
      end
    end

    { error: "Column(s) not found", status: :not_found } unless column_list_for_item_update.length > 0
  end

  sig { returns(ActionController::Parameters) }
  def single_item_update_params
    underscored_params.permit(
      :memex_project_item_id,
      :org,
      :memex_number,
      :memex_id,
      :previous_memex_project_item_id,
      :ui,
      field_ids: [],
      memex_project_column_values: memex_update_column_params
    )
  end

  sig { returns(ActionController::Parameters) }
  def bulk_item_update_params
    underscored_params.permit(
      :org,
      :memex_number,
      :memex_id,
      :ui,
      field_ids: [],
      memex_project_items: [
        :id,
        memex_project_column_values: memex_bulk_update_column_params
      ],
    )
  end

  sig { params(item: MemexProjectItem, params: T::Array[ActionController::Parameters]).returns(T::Array[T::Boolean]) }
  def bulk_update_column_values(item, params)
    params.map do |column_value_params|
      column_to_update = this_memex.find_column_by_name_or_id(column_value_params[:memex_project_column_id])
      item.set_column_value(column_to_update, column_value_params[:value], current_user,
        column_value_params[:append_only])
    end
  end

  # validates column values based on the column data_type
  # returns nil if the value is valid, or string with a reason for failure
  sig { params(column: MemexProjectColumn, value: T.untyped).returns(T.nilable(String)) }
  def validate_column_value_params(column, value)
    case column.data_type.to_sym
    when :title
      unless value.try(:fetch, :title, nil)
        "Value must be an object that contains a \"title\" key"
      end
    when :text
      unless value.is_a?(String)
        return "Value must be a string"
      end

      if NEWLINE_REGEX.match(value)
        "Value must not contain a newline"
      end
    when :assignees, :labels
      ids = value
      unless ids.is_a?(Array) && ids.all? { |value| value.to_i.positive? }
        "Value must be an array of ids"
      end
    when :milestone, :issue_type, :parent_issue
      id = value
      unless id == "" || id.to_i > 0
        "Value must be an id or an empty string to clear"
      end
    when :single_select, :number, :date, :iteration
      # Validation against the actual value will happen in the Model.
      value = value.to_s
      nil
    when :tracked_by
      ids = value
      unless ids.is_a?(Array) && ids.all? { |value| value.is_a? String }
        "Value must be an array of strings"
      end
    else
      "Updates to a column of type #{column.data_type} are not supported"
    end
  end

  # The client sends a value param that can be of many shapes/classes. This
  # attempts to coerce the value that comes in into something that strong_params
  # will not throw on.
  sig do
    params(
      param: T.nilable(ActionController::Parameters)
    ).returns(T.nilable(T.any(Symbol, T::Hash[Symbol, T.untyped])))
  end
  def value_param_type_value(param)
    case param&.fetch(:value, nil)
    when String then :value
    when Numeric then :value
    when Hash then { value: {} }
    when Array then { value: [] }
    when ActionController::Parameters then { value: {} }
    when nil then :value
    end
  end
end
