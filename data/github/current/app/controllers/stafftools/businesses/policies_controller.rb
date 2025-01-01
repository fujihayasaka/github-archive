# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class PoliciesController < BusinessBaseController
      # Policies actions are supported in all environments
      skip_before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:index]

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
        only: [:actions]

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
        only: [:organizations]

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
        only: [:projects]

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
        only: [:repositories]

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
        only: [:teams]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:actions, :teams, :repositories, :index, :organizations, :projects], optional: true

      def index
        render "stafftools/businesses/policies/index"
      end

      def repositories # rubocop:todo GitHub/UseRestfulActions
        view = ::Businesses::Settings::MemberPrivilegesView.new(business: this_business)
        render "stafftools/businesses/policies/repositories", locals: { view: view }
      end

      def actions # rubocop:todo GitHub/UseRestfulActions
        form = Actions::Policy::AllowedActionsForm.new(nil, owner: this_business)
        render "stafftools/businesses/policies/actions", locals: { form: form }
      end

      def projects # rubocop:todo GitHub/UseRestfulActions
        view = ::Businesses::Settings::ProjectsView.new(business: this_business)
        render "stafftools/businesses/policies/projects", locals: { view: view }
      end

      def teams # rubocop:todo GitHub/UseRestfulActions
        view = ::Businesses::Settings::TeamsView.new(business: this_business)
        render "stafftools/businesses/policies/teams", locals: { view: view }
      end

      def organizations # rubocop:todo GitHub/UseRestfulActions
        view = ::Businesses::Settings::OrganizationsView.new(business: this_business)
        render "stafftools/businesses/policies/organizations", locals: { view: view }
      end
    end
  end
end
