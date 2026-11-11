# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class SeatLimitsController < Stafftools::Businesses::BusinessBaseController

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Configurations,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:edit]

      def edit
        render "stafftools/businesses/seat_limits/edit"
      end

      def update
        errors = []
        ApplicationRecord::Domain::ConfigurationEntries.transaction do
          custom_seat_limit_for_upgrades = seat_limit_params.delete(:seat_limit_for_upgrades)&.to_i
          if custom_seat_limit_for_upgrades > 0
            this_business.set_custom_seat_limit_for_upgrades(custom_seat_limit_for_upgrades, current_user)
          else
            errors << "Custom seat limit for upgrades must be greater than 0"
            raise ActiveRecord::Rollback
          end

          custom_seat_limit_for_advanced_security_upgrade = seat_limit_params.delete(:seat_limit_for_advanced_security_upgrade)&.to_i
          if custom_seat_limit_for_advanced_security_upgrade > 0
            this_business.set_custom_seat_limit_for_advanced_security_upgrades(custom_seat_limit_for_advanced_security_upgrade, current_user)
          else
            errors << "Custom seat limit for advanced security upgrades must be greater than 0"
            raise ActiveRecord::Rollback
          end
        end

        if errors.present?
          flash[:error] = errors.join(", ")
        else
          flash[:notice] = "Updated #{this_business.name} seat limits"
        end
        redirect_to stafftools_enterprise_path(this_business)
      end

      private

      def seat_limit_params
        params.require(:business).permit(
          :seat_limit_for_upgrades,
          :seat_limit_for_advanced_security_upgrade,
        )
      end
    end
  end
end
