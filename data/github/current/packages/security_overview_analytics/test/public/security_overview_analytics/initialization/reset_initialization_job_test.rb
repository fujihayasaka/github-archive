# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class ResetInitializationJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        @biz = create(:business)
        @biz2 = create(:business)
      end

      test "resets provided type", skip_enterprise: true do
        type = Initialization::Type::Users
        other_type = Initialization::Type::Organizations

        initialization = SecurityOverviewAnalytics::Initialization.for(@biz)
        initialization.set_type_to_initialized(type: type)
        initialization.set_type_to_initialized(type: other_type)
        assert initialization.initialized?(type:)

        initialization2 = SecurityOverviewAnalytics::Initialization.for(@biz2)
        initialization2.set_type_to_initialized(type: type)
        initialization2.set_type_to_initialized(type: other_type)
        assert initialization2.initialized?(type:)

        ResetInitializationJob.perform_now(business_ids: [@biz.id], type: type.serialize)

        refute initialization.initialized?(type: type)
        assert initialization.initialized?(type: other_type)

        assert initialization2.initialized?(type: type)
        assert initialization2.initialized?(type: other_type)

      end
    end
  end
end
