# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::TradeCompliance
  extend ActiveSupport::Concern
  extend T::Helpers

  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  requires_ancestor { Platform::Objects::Query }

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :stafftools_info, Objects::StafftoolsInfo, visibility: :internal, description: "Stafftools information.", null: true

    def stafftools_info
      if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(@context[:viewer], self.class.name)
        @context[:viewer] # just need to return something other than nil
      else
        nil
      end
    end

    field :account_screening_profiles, Connections.define(Objects::AccountScreeningProfile), visibility: :internal, description: "Account screening profiles", null: true, connection: true do
      argument :screening_status, String, "The account screening profiles screening status.", required: true
    end

    def account_screening_profiles(**arguments)
      if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(@context[:viewer], self.class.name)
        ::AccountScreeningProfile.where(msft_trade_screening_status: arguments[:screening_status])
      else
        nil
      end
    end
  end
end
