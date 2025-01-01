# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class MeteredServerLicensesController < BusinessBaseController
      include ApplicationController::VerifiedFetchDependency

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        ApplicationRecord::Configurations,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      before_action :metered_ghes_required

      allow_verified_fetch only: [:create]

      def show
        ghes_license = this_business.ghes_licenses.find_by(reference_number: params[:id])
        license_key = ghes_license&.license_key
        return render_404 unless license_key
        send_data license_key, filename: ghes_license.license_key_file_name
      end

      def create
        respond_to do |format|
          format.json do
            ghes_license = ::Licensing::GhesLicense.create_metered_ghes_license(business: this_business)
            render json: ghes_license.as_json(only: [:reference_number, :seats, :expires_at], root: false)
          end
        end
      end

      private

      def metered_ghes_required
        render_404 unless this_business.metered_ghes_eligible?
      end
    end
  end
end
