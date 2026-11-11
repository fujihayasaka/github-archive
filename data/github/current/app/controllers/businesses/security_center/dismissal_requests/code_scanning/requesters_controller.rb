# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module DismissalRequests
      module CodeScanning
        class RequestersController < AbstractSecurityCenterController
          skip_before_action :cap_pagination, unless: :robot?

          before_action :check_code_scanning_enabled
          before_action :security_center_required

          depends_on_clusters ApplicationRecord::Mysql1,
          ApplicationRecord::Repositories,
          ApplicationRecord::Mysql5,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Collab,
          ApplicationRecord::Copilot,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Billing,
          ApplicationRecord::Configurations,
          ApplicationRecord::Spokes,
          ApplicationRecord::Iam,
          only: [:index]

          depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::Notify,
          optional: true,
          only: [:index]

          sig { void }
          def index
            requesters = can_view_request_list? ? RulesEngine::Suggestions.bypass_requests_requesters_for(current_business, ::CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE) : []
            render json: helpers.filter_suggestions(requesters)
          end

          private

          sig { returns(T::Boolean) }
          def can_view_request_list?
            ::CodeScanning::AlertDismissalService.is_valid_business_reviewer?(business: current_business, user: current_user)
          end

          sig { override.returns(T.nilable(Symbol)) }
          def authorized_orgs_actions
            nil
          end

          sig { void }
          def check_code_scanning_enabled
            render_404 unless ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
          end
        end
      end
    end
  end
end
