# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveEnvironmentActionsController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :business_owner_required
  before_action :require_custom_pre_receive_hooks_enabled

  stylesheet_bundle :admin
  javascript_bundle :admin

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    @environment = PreReceiveEnvironment.find(params[:id])

    respond_to do |format|
      format.html do
        render partial: "businesses/pre_receive_environments/environment_actions", locals: { environment: @environment }
      end
    end
  end
end
