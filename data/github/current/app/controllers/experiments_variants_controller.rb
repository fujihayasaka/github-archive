# typed: strict
# frozen_string_literal: true

class ExperimentsVariantsController < ApplicationController
  # CAP bypass okay: intended for anonymous users and returns no organization protected data
  skip_before_action :perform_conditional_access_checks, only: [:index, :show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :feature_flags_required

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  sig { void }
  def index
    namespace = provider.assignment_namespaces.find { |namespace| namespace == params[:namespace] }

    if namespace.nil?
      return render json: { error: "Not found" }, status: :not_found
    end

    render json: { name: namespace, variants: provider.variants }
  end

  sig { void }
  def show
    unless provider.variants.has_key?(params[:variant])
      return render json: { error: "Not found" }, status: :not_found
    end

    render json: { name: params[:variant], value: provider.variants[params[:variant]] }
  end

  private

  sig { returns(AzureEXP::Beta::Participant) }
  memoize def participant
    AzureEXP::Beta::Participant.from_visitor(current_visitor)
  end

  sig { returns(AzureEXP::ExpAssignmentProvider) }
  memoize def provider
    AzureEXP::ExpAssignmentProvider.new(participant: participant, namespace: params[:namespace])
  end

  sig { void }
  def feature_flags_required
    render_404 unless FeatureFlag.vexi.enabled?(:experimentation_azure_variant_endpoint, default: false)
  end
end
