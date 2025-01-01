# typed: strict
# frozen_string_literal: true

class Orgs::IssueFieldsSettingsController < Orgs::Controller
  include ResilienceHelper
  include ApplicationController::VerifiedFetchDependency

  # Allowed data types for issue fields, converted to strings for parameter validation
  ALLOWED_DATA_TYPES = T.let(IssueField::DATA_TYPES.keys.map(&:to_s).freeze, T::Array[String])

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_issue_fields_enabled
  before_action :validate_field_params, only: [:create, :update]
  before_action :require_issue_field, only: [:show, :destroy, :update]

  before_action { @selected_link = T.let(:issue_fields_settings, T.nilable(Symbol)) }

  # Required bc client is sending the request using `reactFetch` which doesn't have Rails CSRF token. Enables secure CSRF protection
  allow_verified_fetch only: [:destroy, :create, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    # Rendering the notifications icon synchronously depends on this cluster
    # Can be removed when the feature `notifications_indicator_async_fetch` is released
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :new, :show],
    optional: true

  # Rendering the organization settings depends on these clusters
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    # Rendering enterprise organizations (GHEC / Proxima / GHES) depends on this cluster
    ApplicationRecord::Billing,
    only: [:index, :new, :show]

  UNAVAILABLE_MESSAGE = "Issue fields are currently unavailable. Please try again later."

  class IndexQueryPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issueFieldsSettingsIndexRoute"
    end

    sig { params(organization: Organization, fields: T::Array[IssueField::IssueFieldType]).void }
    def initialize(organization:, fields:)
      @organization = organization
      @fields = fields
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      fields = @fields.map do |field|
        {
          id: field.id.to_s, # TODO issue_fields, use global id instead?
          name: field.name,
          type: field.data_type,
          description: field.description,
        }
      end

      {
        fields: fields,
        organization: {
          login: @organization.display_login,
          id: @organization.id.to_s,
        },
      }
    end
  end

  class NewQueryPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issueFieldsSettingsNewRoute"
    end

    sig { params(organization: Organization, fields: T::Array[IssueField::IssueFieldType]).void }
    def initialize(organization:, fields:)
      @organization = organization
      @fields = fields
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload # TODO update issue field to include prioity
      fields = @fields.map do |field|
        {
          id: field.id.to_s, # TODO issue_fields, use global id instead?
          name: field.name,
          type: field.data_type,
          description: field.description,
        }
      end

      {
        fields: fields,
        organization: {
          login: @organization.display_login,
          id: @organization.id.to_s,
        },
      }
    end
  end

  class EditQueryPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issueFieldsSettingsEditRoute"
    end

    sig { params(organization: Organization, field: IssueField::IssueFieldType, fields: T::Array[IssueField::IssueFieldType]).void }
    def initialize(organization:, field:, fields:)
      @organization = organization
      @field = field
      @fields = fields
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      fields = @fields.map do |field|
        {
          id: field.id.to_s,
          name: field.name,
          type: field.data_type,
          description: field.description,
        }
      end

      field_hash = {
        id: @field.id.to_s,
        name: @field.name,
        type: @field.data_type,
        description: @field.description,
        priority: @field.priority
      }

      # Include options for single select fields
      if @field.data_type.to_sym == :single_select
        # Cast to the concrete implementation to access options
        single_select_field = T.cast(@field, IssueFieldSingleSelect)
        field_hash[:options] = single_select_field.options.sort_by { |option| [option.priority || 0, option.id] }.map do |option|
          {
            id: option.id.to_s,
            name: option.name,
            color: option.color.upcase, # Ensure color is uppercase for consistency with UI
            description: option.description,
            priority: option.priority
          }
        end
      end

      {
        field: field_hash,
        fields: fields,
        organization: {
          login: @organization.display_login,
          id: @organization.id.to_s
        },
      }
    end
  end

  sig { void }
  def index
    with_fallback do
      fields = Issues.domain.issue_fields.by_organization(this_organization)
      title = "Settings · Issue Fields · #{this_organization.display_login}"
      payload = IndexQueryPayload.new(organization: this_organization, fields: fields)

      respond_to do |format|
        format.html do
          render_react_html(
            title: title,
            layout: "layouts/settings/issue_fields",
            payload: payload,
          )
        end

        format.json do
          render_react_json(
            title: title,
            payload: payload,
          )
        end
      end
    end
  end

  sig { void }
  def new
    with_fallback do
      fields = Issues.domain.issue_fields.by_organization(this_organization)

      render_react_html(
        title: "Settings · Issue Fields · #{this_organization.display_login} · Create",
        layout: "layouts/settings/issue_fields",
        payload: NewQueryPayload.new(organization: this_organization, fields: fields),
      )
    end
  end

  sig { void }
  def show
    with_fallback do
      return unless require_issue_field

      # TODO: Do we need the field list (temporary here for used field name validation)
      fields = Issues.domain.issue_fields.by_organization(this_organization)
      field = T.must(@current_issue_field)
      # Cast to the concrete type expected by EditQueryPayload
      concrete_field = T.cast(field, IssueField::IssueFieldType)

      title = "Settings · Issue Fields · #{this_organization.display_login} · #{field.name}"
      payload = EditQueryPayload.new(organization: this_organization, field: concrete_field, fields: fields)

      respond_to do |format|
        format.html do
          render_react_html(
            title: title,
            layout: "layouts/settings/issue_fields",
            payload: payload,
          )
        end

        format.json do
          render_react_json(
            title: title,
            payload: payload,
          )
        end
      end
    end
  end

  sig { void }
  def create
    with_fallback do
      field_attributes = Issues::IssueFieldNewAttributes.new(
        name: params[:name],
        data_type: params[:data_type],
        description: params[:description],
        priority: @param_field_priority
      )

      if params[:data_type] == "single_select"
        options_data = params[:options]
        sorted_keys = options_data.keys.sort_by(&:to_i)
        options_array = sorted_keys.map { |key| options_data[key] }
        options = options_array.map do |option|
          Issues::IssueFieldOptionNewAttributes.new(
            name: option[:name],
            color: option[:color],
            description: option[:description],
            priority: option[:priority].present? ? Integer(option[:priority]) : nil
          )
        end

        result = Issues.domain.issue_fields.create_single_select_field(
          org: this_organization,
          name: field_attributes.name,
          options: options,
          actor: current_user,
          description: field_attributes.description,
          priority: field_attributes.priority
        )
      else
        # For other fields, use the regular method
        result = Issues.domain.issue_fields.create_field(
          org: this_organization,
          name: field_attributes.name,
          data_type: field_attributes.data_type,
          actor: current_user,
          description: field_attributes.description,
          priority: field_attributes.priority
        )
      end

      handle_field_result(result, success_status: :created)
    end
  end

  sig { void }
  def update
    with_fallback do
      attr_hash = {}
      attr_hash[:name] = params[:name] if params.key?(:name)
      attr_hash[:description] = params[:description] if params.key?(:description)
      attr_hash[:priority] = @param_field_priority

      field_attributes = Issues::IssueFieldUpdateAttributes.new(**attr_hash)

      result = nil
      if T.must(@current_issue_field).data_type.to_sym == :single_select
        all_options = params[:options].present? ? JSON.parse(params[:options]) : {}
        sorted_keys = all_options&.keys&.sort_by(&:to_i) # these are the form encoded params

        options_array = sorted_keys&.map { |key| all_options[key] }&.map.with_index do |option, index|
          Issues::IssueFieldOptionUpdateAttributes.new(
            name: option["name"],
            color: option["color"],
            description: option["description"],
            priority: index + 1,
            option_id: option["option_id"].presence.to_i
          )
        end
        result = Issues.domain.issue_fields.update_single_select_field(
          issue_field: T.cast(@current_issue_field, Issues::IIssueFieldSingleSelect),
          field_attributes: field_attributes,
          all_options: options_array,
          org: this_organization
        )
      else
        result = Issues.domain.issue_fields.update_field(
          issue_field: T.must(@current_issue_field),
          field_attributes: field_attributes,
          org: this_organization
        )
      end
      handle_field_result(result)
    end
  end

  sig { void }
  def destroy
    with_fallback do
      issue_field = T.must(@current_issue_field)
      field_id = T.must(issue_field.id)

      result = Issues.domain.issue_fields.delete_field_by_id(field_id, this_organization)
      handle_field_result(result)
    end
  end

  private

  sig { params(result: GH::Result[Issues::IIssueFieldOption], success_status: Symbol).void }
  def handle_field_option_result(result, success_status: :ok)
    case result
    when GH::Result::Ok
      option = result.value
      render json: {
        id: option.id,
        name: option.name,
        color: option.color,
        description: T.cast(option, IssueFieldOption).description,
        priority: option.priority,
      }, status: success_status
    when GH::Result::Error::Validation
      render json: {
        error: result.model.errors.full_messages.join(", ")
      }, status: :unprocessable_entity
    when GH::Result::Error::NotFound
      render json: {
        error: result.message
      }, status: :not_found
    when GH::Result::Error
      render json: {
        error: result.message
      }, status: :unprocessable_entity
    end
  end

  sig do params(
    result: T.any(GH::Result[Issues::IIssueField], GH::Result[Issues::IIssueFieldSingleSelect]),
    success_status: Symbol).void
  end
  def handle_field_result(result, success_status: :ok)
    case result
    when GH::Result::Ok
      field = result.value
      json_result = {
        id: field.id,
        name: field.name,
        data_type: field.data_type,
        description: field.description,
        priority: field.priority
      }
      if field.data_type.to_sym == :single_select
        json_result[:options] = field.options.sort_by { |option| [option.priority || 0, option.id] }.map do |option|
          {
            id: option.id,
            name: option.name,
            color: option.color,
            description: option.description,
            priority: option.priority
          }
        end
      end
      render json: json_result, status: success_status
    when GH::Result::Error::Validation
      render json: {
        error: result.model.errors.full_messages.join(", ")
      }, status: :unprocessable_entity
    when GH::Result::Error::NotFound
      render json: {
        error: result.message
      }, status: :not_found
    when GH::Result::Error
      render json: {
        error: result.message
      }, status: :unprocessable_entity
    end
  end

  sig { void }
  def validate_field_params
    errors = []

    # Validate name is present and not empty for create, but allow blank for update
    if action_name == "create"
      if params[:name].blank?
        errors << "Name can't be blank"
      end
      if params[:data_type].blank?
        errors << "Data type can't be blank"
      elsif !ALLOWED_DATA_TYPES.include?(params[:data_type])
        errors << "Data type must be one of: #{ALLOWED_DATA_TYPES.join(', ')}"
      end

      if params[:data_type] == "single_select"
        if params[:options].blank? || (params[:options].respond_to?(:keys) && params[:options].keys.empty?)
          errors << "Options must be a non-empty array for single_select fields"
        elsif params[:options].present?
          # Handle hash format with numeric keys (multipart form data)
          options_to_check = params[:options]

          sorted_keys = options_to_check.keys.sort_by(&:to_i)
          sorted_keys.each_with_index do |key, index|
            option = options_to_check[key]
            option_errors = validate_single_select_option(option, index: index)
            errors.concat(option_errors)
          end
        end
      end
    elsif action_name == "update"
      # For update, validate name if it's provided and is empty string
      if params.key?(:name) && params[:name].blank?
        errors << "Name can't be blank"
      end
    end

    # Priority is optional for both create and update
    if params[:priority].present?
      begin
        @param_field_priority = T.let(Integer(params[:priority]), T.nilable(Integer))
      rescue ArgumentError
        errors << "Priority must be a valid integer"
      end
    end

    # Return validation errors if any
    unless errors.empty?
      render json: {
        error: errors.join(", ")
      }, status: :unprocessable_entity
    end
  end

  sig { void }
  def validate_field_option_params
    errors = []

    # Validate field_id is present and is an integer
    if params[:id].blank?
      errors << "Field ID is required"
    else
      begin
        @param_field_id = T.let(Integer(params[:id]), T.nilable(Integer))
      rescue ArgumentError
        errors << "Field ID must be a valid integer"
      end
    end

    option_errors = validate_single_select_option(params)
    errors.concat(option_errors)

    if params[:priority].present?
      begin
        @param_field_priority = T.let(Integer(params[:priority]), T.nilable(Integer))
      rescue ArgumentError
        errors << "Priority Field must be a valid integer"
      end
    end

    # Return validation errors if any
    unless errors.empty?
      render json: {
        error: errors.join(", ")
      }, status: :unprocessable_entity
    end
  end

  sig { returns(T::Boolean) }
  def require_issue_field
    unless params[:id].present? && params[:id].to_s.match?(/\A\d+\z/)
      render json: { error: "Missing or invalid issue field id" }, status: :not_found
      false
    end

    field_id = params[:id].to_i
    issue_field = Issues.domain.issue_fields.issue_field_for_org(field_id, this_organization)

    unless issue_field
      render json: { error: "Issue field not found" }, status: :not_found
      return false
    end

    @current_issue_field = T.let(issue_field, T.nilable(Issues::IIssueField))
    true
  end

  sig { params(block: T.proc.void).void }
  def with_fallback(&block)
    with_database_error_fallback(fallback: nil) do
      return yield
    end

    flash[:error] = UNAVAILABLE_MESSAGE
    redirect_back fallback_location: "/"
  end

  sig { params(option: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters), index: T.nilable(Integer)).returns(T::Array[String]) }
  def validate_single_select_option(option, index: nil)
    errors = []
    prefix = index ? "Option #{index + 1}" : "Option"

    unless option.is_a?(Hash) || option.is_a?(ActionController::Parameters)
      errors << "#{prefix} must be a hash"
      return errors
    end

    if option[:name].blank?
      errors << "#{prefix} name can't be blank"
    end

    if option[:color].blank?
      errors << "#{prefix} color can't be blank"
    end

    if action_name == "update" && option[:option_id].blank?
      errors << "#{prefix} option_id is required for update"
    end

    priority_value = option[:priority].presence
    if priority_value.present?
      begin
        Integer(priority_value)
      rescue ArgumentError
        errors << "#{prefix} priority must be a valid integer"
      end
    end

    errors
  end

  sig { void }
  def ensure_issue_fields_enabled
    render_404 unless IssueFieldsFeature.enabled?(this_organization, actor: current_user)
  end
end
