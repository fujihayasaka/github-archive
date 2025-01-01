# typed: true
# frozen_string_literal: true

class Businesses::VirtualNetworkSettingsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  before_action :business_owner_required
  before_action :add_csp_exceptions, only: :new
  allow_verified_fetch only: [:create]

  CSP_EXCEPTIONS = {
    connect_src: ["https://login.microsoftonline.com", "https://management.azure.com"],
  }

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index, :edit, :new]

  before_action :check_feature_flag

  def index
    render "businesses/virtual_network_settings/index", locals: {
      virtual_networks: Codespaces::VirtualNetwork.for_business(this_business)
    }
  end

  def edit
    render "businesses/virtual_network_settings/edit", locals: {
      virtual_network: Codespaces::VirtualNetwork.for_business(this_business).find(params[:id])
    }
  end

  def new
    render_react_app(
      payload: {
        formAction: settings_virtual_networks_path(this_business),
        business: {
          name: this_business.name,
        }
      },
      title: "Add Virtual Network",
      layout: "react_business",
      page_data: {
        selected_link: :virtual_networks,
        sidebar: :settings,
      },
      disable_ssr: true, # disabled until this app is ready for SSR
    )
  end

  def create
    body = JSON.parse(request&.body.read)

    network = Codespaces::VirtualNetwork.new(
      business: this_business,
      subnet_id: body["subnet_id"],
      subnet_name: body["subnet_name"],
      subscription_id: body["subscription_id"],
      subscription_name: body["subscription_name"],
      virtual_network_name: body["virtual_network_name"]
    )

    if network.save
      render json: {
        redirect_url: settings_virtual_networks_path(this_business),
      }, status: :created
    else
      render json: {
        errors: network.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    network = Codespaces::VirtualNetwork.for_business(this_business).find(params[:id])

    if network.destroy
      redirect_to settings_virtual_networks_path(this_business),
        flash: { notice: "Virtual network \"#{network.virtual_network_name}\" deleted" }
    else
      redirect_to :back,
        flash: { error: "Unable to destroy virtual network" }
    end
  end

  private

  def check_feature_flag
    render_404 unless FeatureFlag.vexi.enabled?(:codespaces_vnet_settings, this_business, default: false)
  end
end
