# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    # This report is only used in GHEC
    class EnterpriseUsers
      def data(business_id: nil, **kwargs)
        GitHub.logger.info("Getting enterprise users for business", "gh.business.id": business_id)

        business = Business.find(business_id)
        Business::UsersCsvGenerator.new(business, **kwargs).generate
      end
    end
  end
end
