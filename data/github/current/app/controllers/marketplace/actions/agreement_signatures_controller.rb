# typed: true
# frozen_string_literal: true

class Marketplace::Actions::AgreementSignaturesController < ApplicationController

  before_action :login_required

  layout false

  def create
    accepted = ActiveModel::Type::Boolean.new.cast(params[:accept])

    unless accepted
      flash[:error] = "You must accept the terms of the agreement."
      return redirect_to :back
    end

    action = RepositoryAction.find(params[:action_id])
    agreement = Marketplace::Agreement.find(params[:agreement_id])

    agreement, signed = if params[:org].present?
      org = Organization.find_by_login(params[:org])
      action.sign_developer_agreement(actor: current_user, agreement: agreement, org: org)
    else
      action.sign_developer_agreement(actor: current_user, agreement: agreement)
    end

    unless signed
      flash[:error] = agreement.errors.full_messages.join(", ")
    end

    redirect_to :back
  end

  private

  def target_for_conditional_access
    org = Organization.find_by_login(params.dig(:org))
    return :no_target_for_conditional_access unless org # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    org
  end
end
