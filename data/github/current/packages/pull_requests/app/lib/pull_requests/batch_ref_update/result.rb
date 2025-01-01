# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    class Result < T::Struct
      class Outcome < T::Enum
        enums do
          Success = new("success")
          Error = new("error")
          NoRequests = new("no_requests")
        end
      end

      sig { params(exception: Exception).returns(Result) }
      def self.error(exception:)
        new(outcome: Outcome::Error, exception:)
      end

      const :outcome, Outcome
      const :exception, T.nilable(Exception)
    end
  end
end
