# typed: strict
# frozen_string_literal: true

class AssetStatusController < ApplicationController

  include BillingSettingsHelper
  include OrganizationsHelper
  include ActionView::Helpers::NumberHelper

  # Always render a 404 when billing is disabled.
  # See Application#ensure_billing_enabled.
  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action only: :upgrade do
    T.bind(self, AssetStatusController)

    check_trade_compliance(target: target, feature_type: :cost_management)
  end

  before_action only: :update do
    T.bind(self, AssetStatusController)

    check_trade_compliance(target: target, feature_type: :cost_management, sdn_redirect: true)
  end
  before_action :ensure_target_is_billable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:downgrade]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Ballast,
    only: [:upgrade]

  sig { void }
  def upgrade # rubocop:todo GitHub/UseRestfulActions
    if GitHub.flipper[:billing_lfs_data_packs_disabled].enabled?(target)
      flash[:error] = "Data packs are not available for this account."
      redirect_to billing_url
    else
      respond_to do |format|
        format.json do
          render json: {
            url: url,
            selectors: {
              ".unstyled-delta-data-packs"       => data_pack_change.delta_packs,
              ".unstyled-delta-data-packs-label" => "data pack".pluralize(data_pack_change.delta_packs),
              ".unstyled-total-data-packs"       => data_pack_change.total_packs,
              ".unstyled-total-data-packs-label" => "pack".pluralize(data_pack_change.total_packs),
              ".unstyled-original-price"         => data_pack_change.undiscounted_price.format,
              ".unstyled-total-price"            => data_pack_change.total_price.format,
              ".unstyled-pack-storage-total"     => number_with_delimiter(data_pack_change.storage_quota.round),
              ".unstyled-pack-bandwidth-total"   => number_with_delimiter(data_pack_change.bandwidth_quota.round),
            },
          }
        end

        format.html do
          render "asset_status/upgrade", locals: { data_pack_change: data_pack_change }
        end
      end
    end
  end

  sig { void }
  def downgrade # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: {
          url: url,
          selectors: {
            ".unstyled-total-data-packs"       => data_pack_change.total_packs,
            ".unstyled-total-data-packs-label" => "data pack".pluralize(data_pack_change.total_packs),
            ".unstyled-renewal-price"           => data_pack_change.renewal_price.format,
            ".unstyled-pack-storage-total"      => number_with_delimiter(data_pack_change.storage_quota.round),
            ".unstyled-pack-bandwidth-total"    => number_with_delimiter(data_pack_change.bandwidth_quota.round),
          },
        }
      end

      format.html do
        render "asset_status/downgrade", locals: { data_pack_change: data_pack_change }
      end
    end
  end

  sig { void }
  def update
    data_pack_updater = ::Billing::DataPackUpdater.new(
      target,
      total_packs: total_packs,
      actor: current_user,
    )

    if data_pack_updater.update
      flash[:notice] = "Successfully updated your data plan. Thanks!"
      redirect_to target_billing_path(target)
    else
      flash[:error] = data_pack_updater.error
      redirect_to :back
    end
  end

  private

  # Internal: String AJAX url for the appropriate action.
  sig { returns(String) }
  def url
    if target.organization? && target.business.present?
      data_packs_enterprise_path(target.business)
    else
      if downgrading?
        target_billing_downgrade_data_plan_path(target, packs: total_packs)
      else
        target_billing_upgrade_data_plan_path(target, packs: delta_packs)
      end
    end
  end

  sig { returns(Billing::PlanChange::DataPackChange) }
  memoize def data_pack_change
    Billing::PlanChange::DataPackChange.new(target, total_packs: total_packs)
  end

  sig { returns(Integer) }
  memoize def total_packs
    begin
      if asset_status_params = params[:asset_status]
        if asset_status_params[:total_packs]
          # POST: downgrades specify total packs
          asset_status_params[:total_packs].to_i
        else
          # POST: upgrades specify delta packs to purchase, default to purchasing zero packs
          target.data_packs + asset_status_params.fetch(:delta_packs, 0).to_i
        end
      elsif downgrading?
        # GET: default to current pack count when downgrading
        [(params[:packs] || target.data_packs).to_i, target.data_packs].min
      else
        # GET: default to purchasing one pack
        target.data_packs + (params[:packs] || 1).to_i
      end
    end
  end

  sig { returns(Integer) }
  def delta_packs
    total_packs - target.data_packs.to_i
  end

  sig { returns(T::Boolean) }
  def downgrading?
    action_name == "downgrade"
  end

  helper_method :target
  sig { returns(User) }
  memoize def target
    T.must(nilable_target)
  end

  sig { returns(T.nilable(T.any(User, Organization))) }
  memoize def nilable_target
    begin
      if params[:target] == "organization"
        org = current_organization_for_member_or_billing
        if org && org.billing_manageable_by?(current_user)
          org
        end
      else
        current_user
      end
    end
  end

  sig { void }
  def ensure_target
    render_404 unless nilable_target
  end

  sig { void }
  def ensure_target_is_billable
    render_404 unless target.billable?
  end

  helper_method :allowed_to_purchace_data_packs?
  sig { returns(T::Boolean) }
  def allowed_to_purchace_data_packs?
    return true unless target.live_sdn_screening_enabled?

    !target.has_commercial_interaction_restriction?(feature_type: :cost_management)
  end
end
