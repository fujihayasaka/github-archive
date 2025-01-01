# typed: strict
# frozen_string_literal: true

require "github-launch"

module Launch
  module Twirp
    class ChecksClient < Launch::Twirp::BaseClient

      sig { params(repository: Repository, change_id: Integer, job_id: T.nilable(String), plan_id: T.nilable(String)).returns(TwirpResponse) }
      def steps_for_change_id(repository:, change_id:, job_id:, plan_id:)
        rpc(
          :StepsFromChangeID,
          change_id:,
          repository_id: identity(repository),
          job_id:,
          plan_id:,
        )
      end

      sig { params(repository: Repository, unauthenticated_url: String).returns(TwirpResponse) }
      def get_summary_exchange_url(repository:, unauthenticated_url:)
        rpc(
          :GetSummaryExchangeURL,
          unauthenticated_job_summaries_url: unauthenticated_url,
          repository_id: identity(repository),
        )
      end

      private

      sig { returns(T.class_of(GitHub::Launch::Services::Checks::ChecksClient)) }
      def twirp_class
        GitHub::Launch::Services::Checks::ChecksClient
      end
    end
  end
end
