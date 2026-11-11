# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Domain
    class Usage < GH::Domain::Base
      include GitHub::Memoizer

      # Public: Create a new usage details record for the user with the given ID if none exists, otherwise bump the
      # auth count for the existing record.
      # rubocop:disable Metrics/MethodLength
      sig { params(user_id: Integer).returns(T.nilable(IUsageDetails)) }
      def create_or_update(user_id:)
        UsageDetails.create_or_update(user_id)
      end

      # Public: Check how many times a user has authenticated with GitHub Models.
      sig { params(user_id: Integer).returns(Integer) }
      def auths_count_for_user_id(user_id)
        UsageDetails.auths_count_for_user_id(user_id)
      end
    end
  end
end
