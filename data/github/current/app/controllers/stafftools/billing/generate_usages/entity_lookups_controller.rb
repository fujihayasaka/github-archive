# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    module GenerateUsages
      class EntityLookupsController < StafftoolsController
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
          only: [:index]

        depends_on_clusters ApplicationRecord::Authnd,
          only: [:index],
          optional: true

        def index
          entity_type = params[:entity_type].to_s
          entity_id = params[:entity_id].to_i

          result = case entity_type
          when "customer"
            lookup_customer(entity_id)
          when "actor", "org"
            lookup_user(entity_id)
          when "repo"
            lookup_repo(entity_id)
          else
            { error: "Unknown entity type" }
          end

          render partial: "stafftools/billing/generate_usages/entity_lookups/result",
            locals: { result: },
            layout: false
        end

        private

        def lookup_customer(id)
          return { error: "Please provide a customer ID" } if id <= 0

          customer = Customer.find_by(id: id)
          return { error: "Customer ##{id} not found" } unless customer

          owner = customer.billable_owner
          if owner.is_a?(Business)
            { id: customer.id, type: "Enterprise", name: owner.name, slug: owner.slug }
          elsif owner.is_a?(::User)
            { id: customer.id, type: owner.organization? ? "Organization" : "User", name: owner.login, slug: owner.login }
          else
            { id: customer.id, type: "Unknown", name: customer.name }
          end
        end

        def lookup_user(id)
          return { error: "Please provide an ID" } if id <= 0

          user = ::User.find_by(id: id)
          return { error: "User/Org ##{id} not found" } unless user

          { id: user.id, type: user.organization? ? "Organization" : "User", slug: user.login }
        end

        def lookup_repo(id)
          return { error: "Please provide a repository ID" } if id <= 0

          repo = ::Repository.find_by(id: id)
          return { error: "Repository ##{id} not found" } unless repo

          { id: repo.id, name: repo.name_with_owner }
        end
      end
    end
  end
end
