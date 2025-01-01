# typed: true
# frozen_string_literal: true


module Stafftools
  module Billing
    class TriggerAzureEmissionsController < StafftoolsController
      extend T::Sig

      before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Ballast,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      only: [:show, :trigger_emission]

      depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

      def show
        render("stafftools/billing/trigger_azure_emission/show")
      end

      def trigger_emission # rubocop:todo GitHub/UseRestfulActions
        if params[:emission_date].present?
          year, month, day = params[:emission_date].split("-").map { |s| s.to_i }
          response = ::Billing::Platform::Api::Client.new.admin_trigger_azure_emission(year: year, month: month, day: day)

          if response.is_a?(::Billing::Platform::Api::Error)
            flash[:error] = "Failed to dispatch azure emission"
          else
            flash[:notice] = "Dispatched azure emission for #{params[:emission_date]}"
          end
        end
        redirect_to(action: :show)
      end
    end
  end
end
