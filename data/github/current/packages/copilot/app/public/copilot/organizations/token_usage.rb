# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module TokenUsage
      extend T::Helpers
      extend T::Sig
      include Copilot::Helpers
      include Copilot::Organizations::Signatures

      abstract!

      sig { override.params(assignable: T.any(::User, ::Team)).returns(T.nilable(Time)) }
      def last_token_activity(assignable)
        usage_detail = if assignable.is_a?(::Team)
          Copilot::AggregateUsageDetail.latest_for_users(assignable.members.to_a)
        elsif assignable.is_a?(::User)
          Copilot::AggregateUsageDetail.latest_for_users(assignable)
        end
        return nil unless usage_detail

        T.must(usage_detail.updated_at).time
      end
    end
  end
end
