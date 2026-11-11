# typed: strict
# frozen_string_literal: true

module ExternalIdentities
  class Domain
    class EmuUsers < GH::Domain::Base
      ERROR_DESCRIPTION = T.let("subject_token identity is not recognized", String)

      # Public: Resolves an EMU user through a business OIDC provider and OID claim.
      #
      # business - The Business whose OIDC provider owns the external identity.
      # oid      - The String OID claim to match against ExternalIdentity#external_id.
      #
      # Returns a GH::Result containing the resolved User.
      sig { params(business: Business, oid: String).returns(GH::Result[User]).checked(:always).on_failure(:raise) }
      def by_business_and_oid(business:, oid:)
        ActiveRecord::Base.connected_to(role: :reading) do
          external_identity = find_external_identity_by_oid(business, oid)
          return error if external_identity.nil?

          user = user_for_external_identity(external_identity, business)
          return error if user.nil?

          GH::Result::Ok.new(user)
        end
      end

      private

      sig { params(business: Business, oid: String).returns(T.nilable(ExternalIdentity)) }
      def find_external_identity_by_oid(business, oid)
        provider = business.oidc_provider

        ExternalIdentity.by_provider(provider).is_active.find_sole_by(external_id: oid)
      rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded
        nil
      end

      sig { params(external_identity: ExternalIdentity, business: Business).returns(T.nilable(User)) }
      def user_for_external_identity(external_identity, business)
        user = external_identity.user
        return if user.nil?

        return unless user.is_enterprise_managed?
        return unless user.enterprise_managed_business == business

        user
      end

      sig { returns(GH::Result::Error[T.untyped]) }
      def error
        GH::Result::Error.new(ERROR_DESCRIPTION)
      end
    end
  end
end
