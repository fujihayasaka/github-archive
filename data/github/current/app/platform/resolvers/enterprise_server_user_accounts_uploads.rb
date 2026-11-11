# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseServerUserAccountsUploads < Resolvers::Base
      argument :order_by, Inputs::EnterpriseServerUserAccountsUploadOrder,
        "Ordering options for Enterprise Server user accounts uploads returned from the connection.",
        required: false, default_value: { field: "created_at", direction: "DESC" }

      type Connections.define(Objects::EnterpriseServerUserAccountsUpload), null: false

      def resolve(order_by: nil)
        object.async_owner.then do |owner|
          if owner.is_a?(::Business)
            if !owner.adminable_by?(context[:viewer]) && !context[:viewer].site_admin?
              return EnterpriseInstallationUserAccountsUpload.none
            end
          end
        end

        uploads = object.user_accounts_uploads
        uploads = apply_order_by(uploads, order_by)
      end

      def apply_order_by(scope, order_by)
        return scope if order_by.nil?
        scope.order("enterprise_installation_user_accounts_uploads.#{order_by[:field]} #{order_by[:direction]}")
      end
    end
  end
end
