# typed: strict
# frozen_string_literal: true

class Orgs::IssueFieldsSettingsController < Orgs::Controller
  include ResilienceHelper
  include ApplicationController::VerifiedFetchDependency

  # Allowed data types for issue fields, converted to strings for parameter validation
  ALLOWED_DATA_TYPES = T.let(IssueField::DATA_TYPES.keys.map(&:to_s).freeze, T::Array[String])

  # Allowed visibilities for issue fields, converted to strings for parameter validation
  ALLOWED_VISIBILITIES = T.let(IssueField::VISIBILITIES.keys.map(&:to_s).freeze, T::Array[String])

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_issue_fields_enabled
  before_action :validate_field_params, only: [:create, :update]
  before_action :require_issue_field, only: [:show, :destroy, :update]

  before_action { @selected_link = T.let(:issue_fields_settings, T.nilable(Symbol)) }

  # Required bc client is sending the request using `reactFetch` which doesn't have Rails CSRF token. Enables secure CSRF protection
  allow_verified_fetch only: [:destroy, :create, :update]

  depends_on_clusters ApplicationRecord::Copilot,
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
    ApplicationRecord::Repositories,
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
          visibility: field.visibility,
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

    sig do
      params(
        organization: Organization,
        fields: T::Array[IssueField::IssueFieldType],
        org_pinned_fields_enabled: T::Boolean,
        issue_types: T::Array[T::Hash[Symbol, T.untyped]]
      ).void
    end
    def initialize(organization:, fields:, org_pinned_fields_enabled: false, issue_types: [])
      @organization = organization
      @fields = fields
      @org_pinned_fields_enabled = org_pinned_fields_enabled
      @issue_types = issue_types
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload # TODO update issue field to include prioity
      fields = @fields.map do |field|
        {
          id: field.id.to_s, # TODO issue_fields, use global id instead?
          name: field.name,
          type: field.data_type,
          description: field.description,
          visibility: field.visibility,
        }
      end

      result = {
        fields: fields,
        organization: {
          login: @organization.display_login,
          id: @organization.id.to_s,
        },
        orgPinnedFieldsEnabled: @org_pinned_fields_enabled,
      }

      if @org_pinned_fields_enabled
        result[:issueTypes] = @issue_types
      end

      result
    end
  end

  class EditQueryPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "issueFieldsSettingsEditRoute"
    end

    sig do
      params(
        organization: Organization,
        field: IssueField::IssueFieldType,
        fields: T::Array[IssueField::IssueFieldType],
        org_pinned_fields_enabled: T::Boolean,
        issue_types: T::Array[T::Hash[Symbol, T.untyped]],
        pinned_issue_type_ids: T::Array[Integer],
        pinned_to_issues_with_no_type: T::Boolean
      ).void
    end
    def initialize(organization:, field:, fields:, org_pinned_fields_enabled: false, issue_types: [], pinned_issue_type_ids: [], pinned_to_issues_with_no_type: false)
      @organization = organization
      @field = field
      @fields = fields
      @org_pinned_fields_enabled = org_pinned_fields_enabled
      @issue_types = issue_types
      @pinned_issue_type_ids = pinned_issue_type_ids
      @pinned_to_issues_with_no_type = pinned_to_issues_with_no_type
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      fields = @fields.map do |field|
        {
          id: field.id.to_s,
          name: field.name,
          type: field.data_type,
          description: field.description,
          visibility: field.visibility,
        }
      end

      field_hash = {
        id: @field.id.to_s,
        name: @field.name,
        type: @field.data_type,
        description: @field.description,
        priority: @field.priority,
        visibility: @field.visibility,
      }

      # Include options for select fields
      if @field.data_type.to_sym == :single_select || @field.data_type.to_sym == :multi_select
        # Cast to the concrete implementation to access options
        select_field = T.cast(@field, T.any(IssueFieldSingleSelect, IssueFieldMultiSelect))
        field_hash[:options] = select_field.options.sort_by { |option| [option.priority || 0, option.id] }.map do |option|
          {
            id: option.id.to_s,
            name: option.name,
            color: option.color.upcase, # Ensure color is uppercase for consistency with UI
            description: option.description,
            priority: option.priority
          }
        end
      end

      result = {
        field: field_hash,
        fields: fields,
        organization: {
          login: @organization.display_login,
          id: @organization.id.to_s
        },
        orgPinnedFieldsEnabled: @org_pinned_fields_enabled,
      }

      if @org_pinned_fields_enabled
        result[:issueTypes] = @issue_types
        result[:pinnedIssueTypeIds] = @pinned_issue_type_ids
        result[:pinToNoTypeIssues] = @pinned_to_issues_with_no_type
      end

      result
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
      pinned_enabled = org_pinned_fields_enabled?
      issue_types_data = pinned_enabled ? build_issue_types_with_pinned_counts : []

      render_react_html(
        title: "Settings · Issue Fields · #{this_organization.display_login} · Create",
        layout: "layouts/settings/issue_fields",
        payload: NewQueryPayload.new(
          organization: this_organization,
          fields: fields,
          org_pinned_fields_enabled: pinned_enabled,
          issue_types: issue_types_data
        ),
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

      pinned_enabled = org_pinned_fields_enabled?
      issue_types_data = []
      pinned_issue_type_ids = []
      pinned_to_issues_with_no_type = false

      if pinned_enabled
        issue_types_data = build_issue_types_with_pinned_counts
        pinned_issue_types = Issues.domain.planning_templates.get_pinned_issue_types_for_field(org: this_organization, issue_field: field)
        pinned_issue_type_ids = pinned_issue_types[:issue_type_ids]
        pinned_to_issues_with_no_type = pinned_issue_types[:pinned_to_issues_with_no_type]
      end

      title = "Settings · Issue Fields · #{this_organization.display_login} · #{field.name}"
      payload = EditQueryPayload.new(
        organization: this_organization,
        field: concrete_field,
        fields: fields,
        org_pinned_fields_enabled: pinned_enabled,
        issue_types: issue_types_data,
        pinned_issue_type_ids: pinned_issue_type_ids,
        pinned_to_issues_with_no_type: pinned_to_issues_with_no_type
      )

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
      new_attrs = {
        name: params[:name],
        data_type: params[:data_type],
        description: params[:description],
        priority: @param_field_priority,
        visibility: params[:visibility]
      }
      field_attributes = Issues::IssueFieldNewAttributes.new(**new_attrs)

      if params[:data_type] == "single_select" || params[:data_type] == "multi_select"
        # Check FF for multi_select before any further processing
        if params[:data_type] == "multi_select"
          unless IssueFieldsFeature.multi_select_enabled?(this_organization)
            render json: { error: "Multi-select fields are not enabled for this organization" }, status: :forbidden
            return
          end
        end

        options_data = params[:options]
        sorted_keys = options_data.keys.sort_by(&:to_i)
        options_array = sorted_keys.map { |key| options_data[key] }

        # Auto-assign priority based on position if not provided
        options_array.each_with_index do |option, index|
          option[:priority] = (index + 1).to_s unless option[:priority].present?
        end

        # Validate required fields using shared validator
        begin
          Issues::FieldOptionValidator.validate_options!(options_array)
        rescue Issues::FieldOptionValidator::ValidationError => e
          render json: { error: e.message }, status: :unprocessable_entity
          return
        end

        options = options_array.map do |option|
          Issues::IssueFieldOptionNewAttributes.new(
            name: option[:name],
            color: option[:color],
            description: option[:description],
            priority: option[:priority].present? ? Integer(option[:priority]) : nil
          )
        end

        create_select_args = {
          org: this_organization,
          name: field_attributes.name,
          options: options,
          actor: current_user,
          description: field_attributes.description,
          priority: field_attributes.priority,
          visibility: field_attributes.visibility
        }

        if params[:data_type] == "multi_select"
          result = Issues.domain.issue_fields.create_multi_select_field(**create_select_args)
        else
          result = Issues.domain.issue_fields.create_single_select_field(**create_select_args)
        end
      else
        # For other fields, use the regular method
        create_field_args = {
          org: this_organization,
          name: field_attributes.name,
          data_type: field_attributes.data_type,
          actor: current_user,
          description: field_attributes.description,
          priority: field_attributes.priority,
          visibility: field_attributes.visibility
        }
        result = Issues.domain.issue_fields.create_field(**create_field_args)
      end

      # Handle pinning if the field was created successfully
      case result
      when GH::Result::Ok
        field = result.value
        pin_field_to_types(field)
        render_field_with_pin_status(field, :created)
      else
        handle_field_result(result, success_status: :created)
      end
    end
  end

  sig { void }
  def update
    with_fallback do
      attr_hash = {}
      attr_hash[:name] = params[:name] if params.key?(:name)
      attr_hash[:description] = params[:description] if params.key?(:description)
      attr_hash[:priority] = @param_field_priority
      attr_hash[:visibility] = params[:visibility] if params.key?(:visibility)

      field_attributes = Issues::IssueFieldUpdateAttributes.new(**attr_hash)

      result = nil
      if T.must(@current_issue_field).data_type.to_sym == :single_select || T.must(@current_issue_field).data_type.to_sym == :multi_select
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

        if T.must(@current_issue_field).data_type.to_sym == :multi_select
          unless IssueFieldsFeature.multi_select_enabled?(this_organization)
            render json: { error: "Multi-select fields are not enabled for this organization" }, status: :forbidden
            return
          end
          result = Issues.domain.issue_fields.update_multi_select_field(
            issue_field: T.cast(@current_issue_field, Issues::IIssueFieldMultiSelect),
            field_attributes: field_attributes,
            all_options: options_array,
            org: this_organization
          )
        else
          result = Issues.domain.issue_fields.update_single_select_field(
            issue_field: T.cast(@current_issue_field, Issues::IIssueFieldSingleSelect),
            field_attributes: field_attributes,
            all_options: options_array,
            org: this_organization
          )
        end
      else
        result = Issues.domain.issue_fields.update_field(
          issue_field: T.must(@current_issue_field),
          field_attributes: field_attributes,
          org: this_organization
        )
      end

      # Handle pinning if the field was updated successfully
      case result
      when GH::Result::Ok
        field = result.value
        pin_field_to_types(field)
        render_field_with_pin_status(field, :ok)
      else
        handle_field_result(result)
      end
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
    result: T.any(GH::Result[Issues::IIssueField], GH::Result[Issues::IIssueFieldSingleSelect], GH::Result[Issues::IIssueFieldMultiSelect]),
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
        priority: field.priority,
        visibility: field.visibility
      }
      if field.data_type.to_sym == :single_select || field.data_type.to_sym == :multi_select
        json_result[:options] = field.options.sort_by { |option| [option.priority || 0, option.id] }.map do |option|
          {
            id: option.id.to_s,
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
      if params[:visibility].blank?
        errors << "Visibility can't be blank"
      elsif !ALLOWED_VISIBILITIES.include?(params[:visibility])
        errors << "Visibility must be one of: #{ALLOWED_VISIBILITIES.join(', ')}"
      end

      if params[:data_type] == "single_select" || params[:data_type] == "multi_select"
        if params[:options].blank? || (params[:options].respond_to?(:keys) && params[:options].keys.empty?)
          errors << "Options must be a non-empty array for #{params[:data_type]} fields"
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
      if params[:visibility].blank?
        errors << "Visibility can't be blank"
      elsif !ALLOWED_VISIBILITIES.include?(params[:visibility])
        errors << "Visibility must be one of: #{ALLOWED_VISIBILITIES.join(', ')}"
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

    # Validate pinning params
    # pinned_issue_type_ids[] comes as an Array from Rails multipart form parsing
    if params[:pinned_issue_type_ids].present?
      # Filter out empty strings that may come from form submissions
      ids = params[:pinned_issue_type_ids].reject { |id| id.blank? }
      params[:pinned_issue_type_ids] = ids
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

  sig { returns(T::Boolean) }
  def org_pinned_fields_enabled?
    # Org-level pinned fields are enabled when the base issue_fields feature is enabled
    IssueFieldsFeature.enabled?(this_organization, actor: current_user)
  end

  # Build issue types array with pinned field counts for the UI.
  # This allows the UI to disable issue types that have reached the max pinned fields limit (10).
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def build_issue_types_with_pinned_counts
    # Use organization.issue_types to get IssueType models with full attributes (color, description)
    issue_types = this_organization.issue_types.select(&:enabled?)
    planning_template = Issues.domain.planning_templates.get_for_org(this_organization)

    # Get pinned field counts per issue type
    pinned_counts_by_type = if planning_template
      PlanningTemplatesTypeFieldsMapping
        .where(owner_id: planning_template.owner_id, planning_template: planning_template)
        .group(:issue_type_id)
        .count
    else
      {}
    end

    # Get pinned field count for "no type" issues
    no_type_pinned_count = if planning_template
      PlanningTemplatesPinnedField.where(owner: this_organization, planning_template: planning_template).count
    else
      0
    end

    # Build the "issues without a type" entry first
    no_type_entry = {
      id: nil,
      name: "Issues without a type",
      color: nil,
      description: "When the issue has no type",
      isEnabled: true,
      pinnedFieldsCount: no_type_pinned_count
    }

    # Map issue types to their hash representation
    type_entries = issue_types.map do |issue_type|
      {
        id: issue_type.id.to_s,
        name: issue_type.name,
        color: issue_type.color.upcase,
        description: issue_type.description,
        isEnabled: issue_type.enabled?,
        pinnedFieldsCount: pinned_counts_by_type[issue_type.id] || 0
      }
    end

    [no_type_entry] + type_entries
  end

  sig { params(field: Issues::IIssueField).returns(T::Boolean) }
  def pin_field_to_types(field)
    # Only process pinning if org-level pinned fields are enabled
    return false unless org_pinned_fields_enabled?

    has_pinning_params = params.key?(:pinned_issue_type_ids) || params.key?(:pin_to_no_type_issues)
    return false unless has_pinning_params

    issue_type_ids = params[:pinned_issue_type_ids] || []
    pinned_to_issues_with_no_type = ActiveModel::Type::Boolean.new.cast(params[:pin_to_no_type_issues]) || false

    result = Issues.domain.planning_templates.update_issue_type_pinning_for_field(
      org: this_organization,
      issue_field: field,
      issue_type_ids: issue_type_ids.map(&:to_i),
      pinned_to_issues_with_no_type: pinned_to_issues_with_no_type
    )

    result.is_a?(GH::Result::Ok)
  end

  sig do
    params(
      field: Issues::IIssueField,
      status: Symbol
    ).void
  end
  def render_field_with_pin_status(field, status)
    json_result = {
      id: field.id,
      name: field.name,
      data_type: field.data_type,
      description: field.description,
      priority: field.priority,
      visibility: field.visibility
    }

    if org_pinned_fields_enabled?
      pins = Issues.domain.planning_templates.get_pinned_issue_types_for_field(org: this_organization, issue_field: field)
      json_result[:pinned_issue_type_ids] = pins[:issue_type_ids]
      json_result[:pin_to_no_type_issues] = pins[:pinned_to_issues_with_no_type]
    end

    if field.data_type.to_sym == :single_select || field.data_type.to_sym == :multi_select
      # Cast to the concrete implementation to access options
      select_field = T.cast(field, T.any(Issues::IIssueFieldSingleSelect, Issues::IIssueFieldMultiSelect))
      json_result[:options] = select_field.options.sort_by { |option| [option.priority || 0, option.id] }.map do |option|
        {
          id: option.id.to_s,
          name: option.name,
          color: option.color,
          description: option.description,
          priority: option.priority
        }
      end
    end
    render json: json_result, status: status
  end
end
