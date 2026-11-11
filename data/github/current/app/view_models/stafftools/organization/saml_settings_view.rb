# typed: true
# frozen_string_literal: true

module Stafftools
  module Organization
    class SamlSettingsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization, :page, :filter, :query, :external_identity_search, :external_user_search

      def linked_members
        return @linked if @linked

        external_identities = organization.saml_provider.external_identities
        if query.present? && external_identity_search
          external_identities = external_identities.where(external_identity_search, "%#{query}%")
        end

        members_ids = external_identities.user_identities.pluck(:user_id)

        users = if query.present? && external_user_search
          ::User.batched_scope(:id, values: members_ids) { |scope| scope.where(external_user_search, "%#{query}%") }
        else
          ::User.batched_scope(:id, values: members_ids)
        end

        users = users.order(:login)

        @linked = users
      end

      def unlinked_members
        @unlinked ||= organization.unlinked_saml_members.sort_by(&:login)
      end

      def scope_title
        "#{scope.capitalize} SAML members"
      end

      def scope
        filter == "unlinked" ? "unlinked" : "linked"
      end

      def scoped_members
        return @scoped if @scoped

        @scoped = case scope
        when "unlinked"
          unlinked_members
        else
          linked_members
        end

        @scoped = @scoped.paginate(page: page.to_i)
      end
    end
  end
end
