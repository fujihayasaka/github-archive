# typed: true
# frozen_string_literal: true

require "csv"

module Stafftools
  class SecurityIncidentResponseDataController < StafftoolsController
    extend T::Sig

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:index]

    def index
      return render_404 unless current_user.security_incident_response_access?
      render "stafftools/security_incident_response/process_csv"
    end

    def create
      return render_404 unless current_user.security_incident_response_access?
      csv = params[:orgs_csv]

      begin
        processed = SecurityIncidentResponse::DataProcessor.new.process(csv)
        timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
        send_data processed.csv, filename: "#{timestamp}_processed.csv"
      rescue SecurityIncidentResponse::DataProcessor::DataProcessingError => e
        flash[:error] = e.message
        redirect_to stafftools_security_incident_response_data_path
      rescue => e
        flash[:error] = "Unexpected error: #{e.message}"
        redirect_to stafftools_security_incident_response_data_path
      end
    end
  end
end
