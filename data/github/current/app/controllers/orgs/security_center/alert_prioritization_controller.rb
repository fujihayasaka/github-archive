# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class AlertPrioritizationController < AbstractSecurityCenterController
      extend T::Sig
      include ApplicationController::VerifiedFetchDependency

      allow_verified_fetch only: [:enqueue_copilot_prompt_experiment]

      before_action :organization_read_required

      # Telemetry
      track_latency_slo "p99-ui-request", 2500, only: [:index]
      track_latency_slo "p50-ui-request", 750, only: [:index]
      track_availability_slo "ui-request", only: [:index]

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Copilot,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        only: [:index]

      sig { void }
      def index
        head :ok
      end

      sig { void }
      def enqueue_copilot_prompt_experiment # rubocop:disable GitHub/UseRestfulActions
        return render_404 unless alert_prioritization_owner_csv_job_ui_enabled?

        ::SecurityCenter::AlertPrioritization::CopilotPromptExperiments::OwnerCsvJob.perform_later(actor: current_user, owner: this_organization)

        head :ok
      end

      instrument_method(:enqueue_copilot_prompt_experiment)

      private

      sig { returns(T::Boolean) }
      memoize def alert_prioritization_owner_csv_job_ui_enabled?
        ::SecurityCenter::FeatureFlagHelper.alert_prioritization_owner_csv_job_ui_enabled?(current_user, this_organization)
      end
    end
  end
end
