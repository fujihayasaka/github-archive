# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module StatusChecks
      class Loader
        include GitHub::ResilienceMixin
        include PullRequests::External::Domain::StatusChecks::Provider

        Result = T.type_alias do
          T.nilable(T.all(
            Object,
            T::Enumerable[StatusChecksSerializer::StatusCheckModel]
          ))
        end

        sig do
          params(
            repository: Repositories::IRepository,
            pull_request: PullRequest,
            avatar_size: Integer,
          ).returns(Result)
        end
        def self.load(repository:, pull_request:, avatar_size:)
          new(repository:, pull_request:, avatar_size:).load
        end

        sig do
          params(
            repository: Repositories::IRepository,
            pull_request: PullRequest,
            avatar_size: Integer,
          ).void
        end
        def initialize(repository:, pull_request:, avatar_size:)
          @repository = repository
          @pull_request = pull_request
          @avatar_size = avatar_size
        end

        sig { returns(Result) }
        def load
          GitHub::PrefillAssociations.prefill_associations(
            @pull_request,
            [:repository, :issue],
            available_records: [@repository]
          )

          with_database_error_fallback(fallback: nil) do
            preloader = PullRequests::PageData::StatusChecks::Preloader.new(
              @repository,
              avatar_size: @avatar_size,
            )
            status_checks_domain.for_pull_request(@pull_request, preloader:)
          rescue GitRPC::ObjectMissing
            nil
          end
        end
      end
    end
  end
end
