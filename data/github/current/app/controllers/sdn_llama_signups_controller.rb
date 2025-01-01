# typed: strict
# frozen_string_literal: true

class SdnLlamaSignupsController < ApplicationController
  include TradeControlsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    only: [:new], optional: true

  before_action :login_required, only: :create

  before_action only: :new do
    T.bind(self, SdnLlamaSignupsController)
    check_trade_compliance
  end

  before_action only: :create do
    T.bind(self, SdnLlamaSignupsController)
    check_trade_compliance(redirect_url: llama2_show_path)
  end

  javascript_bundle :billing
  stylesheet_bundle "site"

  sig { void }
  def new
    render "sdn_llama_signups/new"
  end

  # this action is called when a user who haven't requested access but has an SDN allowed status
  # clicks the "Request access" button
  sig { void }
  def create
    trade_screening_record = current_user.trade_screening_record
    metadata = trade_screening_record.metadata.merge({ llama2_access: { dwh_data_sent: false } })
    if trade_screening_record.update(metadata: metadata)
      trade_screening_record.send_llama2_access_request
    else
      flash[:error] = "There was an error requesting access to ONNX optimized Llama 2 models. Please try again."
    end
    redirect_to llama2_show_path
  end

  # This action is called when a user that wants llama 2 access updates their billing information
  sig { void }
  def update
    # Will be swapped with billing contact update in future
    if update_trade_screening_record(skip_redirect: true)
      flash[:notice] = "Successfully updated account details."
    else
      flash[:error] = "An error occurred while saving account details."
    end

    redirect_to llama2_show_path
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
