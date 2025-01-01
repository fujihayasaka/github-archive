# typed: true
# frozen_string_literal: true

class Stafftools::Users::AdvancedSecurityController < StafftoolsController
  layout "layouts/stafftools/organization/billing"

  before_action :ensure_user_exists
  before_action :ensure_billing_enabled
  before_action :ensure_org, except: [:change_advanced_security]
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:download_active_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:download_maximum_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:download_ghas_repositories]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :download_active_committers, :download_maximum_committers], optional: true

  track_latency_slo "p99-ui-request", 2000, only: [:change_advanced_security]
  track_latency_slo "p50-ui-request", 500, only: [:change_advanced_security]
  track_availability_slo "ui-request", only: [:change_advanced_security]

  def change_advanced_security # rubocop:todo GitHub/UseRestfulActions
    if !this_user.organization?
      flash[:error] = "Unable to set Advanced Security state for non-organization"
    elsif this_user.delegate_billing_to_business?
      flash[:error] = "Unable to set Advanced Security state for organization in enterprise account"
    else
      begin
        if params[:state] == Stafftools::AdvancedSecurityHelper::GHAS_STATE_DISABLED
          disable_ghas
        elsif params[:state] == Stafftools::AdvancedSecurityHelper::GHAS_STATE_UNLIMITED
          make_ghas_unlimited
        elsif params[:state] == Stafftools::AdvancedSecurityHelper::GHAS_STATE_SEATS
          seats = params[:seats].to_i
          update_ghas_seat_count(seats)
        else
          flash[:error] = "Advanced Security state '%s' not recognised" % params[:state]
        end
      rescue Configurable::AdvancedSecurityBillingConfig::Error => e
        flash[:error] = e.message
      end
    end
    redirect_to :back
  end

  def show
    skus = [GitHub::Turboghas::SKU::Bundled]
    if !this_user.advanced_security_products_bundled?
      skus = [GitHub::Turboghas::SKU::CodeSecurity, GitHub::Turboghas::SKU::SecretSecurity]
    end

    render "stafftools/users/advanced_security/show", locals: {
      skus:,
    }
  end

  def toggle_ghas # rubocop:todo GitHub/UseRestfulActions
    enable_ghas = params[:enable_ghas] == "1"

    unless this_user.plan.business?
      flash[:error] = "Cannot turn on/off Advanced Security for this org"
      redirect_to :back
      return
    end

    if enable_ghas
      this_user.set_customer_to_split_metered_offering(actor: current_user)
    else
      this_user.mark_advanced_security_as_not_purchased_for_entity(actor: current_user)
    end
    flash[:info] = "Successfully #{enable_ghas ? "enabled" : "disabled" } advanced security"
    redirect_to :back
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_user, committer_type: :ACTIVE_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])), filename: "ghas_active_committers_#{this_user.login}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_user, committer_type: :MAXIMUM_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])), filename: "ghas_maximum_committers_#{this_user.login}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_ghas_repositories # rubocop:todo GitHub/UseRestfulActions
    csv = CSV.generate do |row|
      row << ["Organization / repository"]
      RepositorySecurityCenterConfig.where(owner: this_user, ghas_enabled: true).includes(:repository).find_each do |config|
        repository = config.repository
        next unless repository
        row << [repository.name_with_owner]
      end
    end

    send_data csv, filename: "ghas_repositories_#{this_user.login}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  private

  def disable_ghas
    if FeatureFlag.vexi.enabled?(:ghas_self_serve_orgs, this_user, default: false)
      if this_user.has_active_advanced_security_subscription?
        this_user.advanced_security_subscription_item.cancel_and_refund!
        flash[:info] = "Job to cancel and refund the Advanced Security subscription is in progress"
      else
        flash[:error] = "Unable to cancel Advanced Security as there is no active subscription for this account"
      end
    else
      if this_user.advanced_security_purchased_for_entity? && this_user.advanced_security_seats_for_entity == 0
        message = {
          organization_id: this_user.id,
          action: :ENDED,
          trial_sku: :ADVANCED_SECURITY,
          converted_to_paid: false,
          **this_user.advanced_security_usage_stats
        }
        GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
      end
      this_user.mark_advanced_security_as_not_purchased_for_entity(actor: current_user)
      this_user.set_advanced_security_seats_for_entity(seats: 0, actor: current_user)
      flash[:info] = default_success_message
    end
  end

  def make_ghas_unlimited
    if FeatureFlag.vexi.enabled?(:ghas_self_serve_orgs, this_user, default: false)
      # If a GHAS trial is allowed for standalone Organizations, this might have to be changed
      flash[:error] = "Unable to set Advanced Security to unlimited seats for self-serve organizations"
    else
      this_user.mark_advanced_security_as_purchased_for_entity(actor: current_user, is_stafftools_action: true)
      this_user.set_advanced_security_seats_for_entity(seats: 0, actor: current_user, is_stafftools_action: true)
      message = {
        organization_id: this_user.id,
        action: :STARTED,
        trial_sku: :ADVANCED_SECURITY,
        start_method: :STAFFTOOLS,
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
      flash[:info] = default_success_message
    end
  end

  def update_ghas_seat_count(seats)
    if seats <= 0
      return flash[:error] = "Number of Advanced Security seats must be a positive integer"
    end
    if FeatureFlag.vexi.enabled?(:ghas_self_serve_orgs, this_user, default: false)
      if !this_user.has_active_advanced_security_subscription?
        this_user.subscribe_to_advanced_security(seats: seats, actor: current_user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month, is_stafftools_action: true)
      else
        this_user.set_advanced_security_seats_for_entity(seats: seats, actor: current_user, is_stafftools_action: true)
      end
    else
      if this_user.advanced_security_purchased_for_entity? && this_user.advanced_security_seats_for_entity == 0
        message = {
          organization_id: this_user.id,
          action: :ENDED,
          trial_sku: :ADVANCED_SECURITY,
          converted_to_paid: true,
          **this_user.advanced_security_usage_stats
        }
        GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
      end
      this_user.mark_advanced_security_as_purchased_for_entity(actor: current_user, is_stafftools_action: true)
      this_user.set_advanced_security_seats_for_entity(seats: seats, actor: current_user, is_stafftools_action: true)
    end
    flash[:info] = default_success_message
  end

  def default_success_message
    "Advanced Security state updated"
  end

  def ensure_org
    render_404 unless this_user.is_a?(Organization)
  end
end
