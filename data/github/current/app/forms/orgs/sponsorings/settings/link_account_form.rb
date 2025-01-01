# typed: strict
# frozen_string_literal: true

module Orgs
  module Sponsorings
    module Settings
      class LinkAccountForm < ApplicationForm
        extend T::Sig

        form do |link_account_form|
          T.bind(self, LinkAccountForm)

          link_account_form.select_list(
            name: "linked_organization_id",
            label: "Linked account",
          ) do |organization_select|
            owned_organizations.each do |org|
              organization_select.option(
                label: org == organization ? "(none)" : org.display_login,
                value: org.id,
                selected: org.id == linked_organization_id,
                test_selector: "link-org-#{org.id}",
              )
            end
          end

          link_account_form.submit(
            name: :submit,
            label: "Link account",
            scheme: :primary,
          )
        end

        sig do
          params(
            organization: Organization,
            owned_organizations: T.any(T::Array[Organization], ActiveRecord::Relation),
            linked_organization_id: T.nilable(Integer)
          ).void
        end
        def initialize(organization:, owned_organizations:, linked_organization_id:)
          @organization           = organization
          @owned_organizations    = owned_organizations
          @linked_organization_id = linked_organization_id
        end

        private

        sig { returns(Organization) }
        attr_reader :organization

        sig { returns(T.any(T::Array[Organization], ActiveRecord::Relation)) }
        attr_reader :owned_organizations

        sig { returns(T.nilable(Integer)) }
        attr_reader :linked_organization_id
      end
    end
  end
end
