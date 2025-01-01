# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class PoliciesController < BusinessBaseController
      # Policies actions are supported in all environments
      skip_before_action :dotcom_required

      depends_on_clusters \
        ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Configurations,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot, only: [:index, :show], optional: true

      def index
        render "stafftools/businesses/policies/index"
      end

      def show
        render_policies_group
      end

      private

      def policies_group
        params[:policies_group].to_s
      end

      def render_policies_group
        case policies_group
        when "repositories"
          view = ::Businesses::Settings::MemberPrivilegesView.new(business: this_business)
          render "stafftools/businesses/policies/repositories", locals: { view: view }
        when "actions"
          form = Actions::Policy::AllowedActionsForm.new(nil, owner: this_business)
          render "stafftools/businesses/policies/actions", locals: { form: form }
        when "projects"
          view = ::Businesses::Settings::ProjectsView.new(business: this_business)
          render "stafftools/businesses/policies/projects", locals: { view: view }
        when "code_security"
          view = ::Businesses::Settings::CodeSecurityView.new(business: this_business, page: current_page)
          render "stafftools/businesses/policies/code_security", locals: { view: view }
        when "personal-access-tokens"
          render "stafftools/businesses/policies/personal_access_tokens"
        else
          render_404
        end
      end
    end
  end
end
