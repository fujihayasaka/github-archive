# typed: strict
# frozen_string_literal: true

class Billing::Settings::DowngradeDialogComponent < ApplicationComponent

  include AnalyticsHelper
  include PlanDowngradeHelper

  sig { returns(GitHub::Plan) }
  attr_reader :current_plan

  sig { returns(GitHub::Plan) }
  attr_reader :new_plan

  sig { returns(T.nilable(Organization)) }
  attr_reader :organization

  sig { returns(T::Boolean) }
  attr_reader :show_button

  sig { returns(Symbol) }
  attr_reader :dialog_button_style

  sig { returns(String) }
  attr_reader :dialog_id

  # Style of the show button used to display the downgrade dialog
  DEFAULT_DIALOG_BUTTON_STYLE = :comparison_button
  DIALOG_BUTTON_STYLE_OPTIONS = T.let([:comparison_button].freeze, T::Array[Symbol])

  sig do
    params(
      current_plan: GitHub::Plan,
      new_plan: GitHub::Plan,
      organization: T.nilable(Organization),
      show_button: T::Boolean,
      dialog_button_style: Symbol,
      dialog_id: String,
    ).void
  end
  def initialize(
    current_plan:,
    new_plan:,
    organization: nil,
    show_button: true,
    dialog_button_style: DEFAULT_DIALOG_BUTTON_STYLE,
    dialog_id: "plan-downgrade-dialog-#{new_plan.name}"
  )
    @current_plan = T.let(current_plan, GitHub::Plan)
    @new_plan = T.let(new_plan, GitHub::Plan)
    @organization = T.let(organization, T.nilable(Organization))
    @show_button = T.let(show_button, T::Boolean)
    @dialog_button_style = T.let(fetch_or_fallback(DIALOG_BUTTON_STYLE_OPTIONS, dialog_button_style, DEFAULT_DIALOG_BUTTON_STYLE), Symbol)
    @dialog_id = T.let(dialog_id, String)
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def show_button_props
    case @dialog_button_style
    when :comparison_button
      {
        scheme: :default,
        classes: "btn-sm btn-block",
        test_selector: "downgrade-dialog-button",
        data: {
          **show_analytics
        }
      }
    end
  end

  sig { returns(T.untyped) }
  def show_analytics
    account_type = "Organization" if @organization.present?
    plan_name = @new_plan.display_name(account_type).titleize
    button_text = "Downgrade to #{plan_name}"

    analytics_click_attributes(
      category: "#{analytics_account_prefix(@organization || current_user)} #{button_text}",
      action: "click to #{button_text}",
      label: "ref_cta:#{button_text};ref_loc:compare_plans"
    )
  end

  sig { returns(T::Hash[String, String]) }
  def submit_button_data
    T.cast(
      downgrade_action_attributes(plan: current_plan, downgrade: new_plan, path: request&.path_info),
      T::Hash[String, String]
    ).merge({
      "submit-dialog-id": dialog_id,
    })
  end

  sig { returns(T::Hash[String, String]) }
  def keep_button_data
    T.cast(
      downgrade_exit_attributes(plan: current_plan, downgrade: new_plan, exit: "Clicked keep button", path: request&.path_info),
      T::Hash[String, String]
    ).merge({
      "close-dialog-id": dialog_id,
    })
  end

  sig { returns(T::Hash[String, String]) }
  def support_button_data
    T.cast(
      downgrade_exit_attributes(plan: current_plan, downgrade: new_plan, exit: "Clicked contact support link", path: request&.path_info),
      T::Hash[String, String]
    )
  end

  sig { returns(T::Hash[String, String]) }
  def closed_dialog_data
    T.cast(
      downgrade_exit_attributes(plan: current_plan, downgrade: new_plan, exit: "Closed dialog", path: request&.path_info),
      T::Hash[String, String]
    ).merge({
      "target": "downgrade-dialog.hiddenCloseInformation"
    })
  end

  sig { returns(T.any(User, Organization)) }
  def target
    @organization || current_user
  end

  sig { returns(String) }
  def fragment_path
    if organization.present?
      settings_org_plan_downgrade_path(plan: new_plan.name, organization_id: organization)
    else
      settings_user_billing_plan_downgrade_path
    end
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  memoize def downgrade_path_and_method
    T.let(
      if current_plan == GitHub::Plan.business_plus && new_plan == GitHub::Plan.business
        { path: org_switch_to_seats_path(@organization, new_plan: @new_plan.name), method: :put }
      elsif current_plan == GitHub::Plan.business_plus && new_plan == GitHub::Plan.free
        { path: cancel_org_seats_path(@organization), method: :delete }
      elsif current_plan == GitHub::Plan.business && new_plan == GitHub::Plan.free
        { path: cancel_org_seats_path(@organization), method: :delete }
      elsif current_plan == GitHub::Plan.pro && new_plan == GitHub::Plan.free
        { path: cc_update_path, method: :post }
      else
        { path: cc_update_path, method: :post }
      end,
      T::Hash[Symbol, T.any(String, Symbol)],
    )
  end

  sig { returns(T::Boolean) }
  def downgrade_disabled
    organization.present? && current_plan.business_plus? && T.must(organization).all_custom_roles.count > 0
  end
end
