# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module EmuChecks
        def can_viewer_access_business(business)
          if business.present?
            return false unless @context[:viewer].present?
            return business == viewer_business if @context[:viewer].bot?
            return business == @context[:viewer].enterprise_managed_business if @context[:viewer].is_enterprise_managed?
          end
        end

        def viewer_business
          if @context[:viewer]&.installation&.target&.organization?
            @context[:viewer]&.installation&.target&.business
          elsif @context[:viewer]&.installation&.target&.user?
            @context[:viewer]&.installation&.target&.enterprise_managed_business
          end
        end
      end
    end
  end
end
