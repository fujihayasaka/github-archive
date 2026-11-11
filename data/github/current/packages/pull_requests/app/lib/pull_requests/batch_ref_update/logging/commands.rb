# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    module Logging
      # This class implements the ICommand interface, and delegates behavior to the relevant Command. This allows us
      # to inject logging without having to pollute the other Command implementations with logging details.
      class Commands
        include ICommand

        class Action < T::Struct
          const :name, Symbol
          const :identifiers, T::Array[String]
          const :context, T.nilable(String)

          # Struct does not natively support ==, this allows for test assertions to work as expected.
          sig { params(other: T.untyped).void }
          def ==(other)
            case other
            when Action
              name == other.name && identifiers == other.identifiers && context == other.context
            else
              super
            end
          end
        end

        module Factories
          sig { params(requests: T::Array[Request]).returns(Action) }
          def did_mark_requests_as_processing(requests:)
            Action.new(name: :mark_requests_as_processing, identifiers: requests.map(&:identifier))
          end

          sig { params(requests: T::Array[Request]).returns(Action) }
          def did_delete_processing_requests(requests:)
            Action.new(name: :delete_processing_requests, identifiers: requests.map(&:identifier))
          end

          sig { params(requests: T::Array[Request::Eligible]).returns(T::Array[Action]) }
          def did_update_refs(requests:)
            requests.map do |request|
              Action.new(
                name: :update_refs,
                identifiers: [request.identifier],
                context: "#{request.ref_name}: #{short_sha(request.before_sha)} => #{short_sha(request.after_sha)}"
              )
            end
          end

          sig { params(request: Request, reason: Enums::Failures).returns(Action) }
          def did_dispatch_request_failure(request:, reason:)
            Action.new(name: :delete_processing_requests, identifiers: [request.identifier])
          end

          private

          sig { params(sha: T.nilable(String)).returns(String) }
          def short_sha(sha)
            sha.to_s[0..6] || "null"
          end
        end

        include Factories

        sig { returns(T::Array[Action]) }
        attr_reader :actions

        sig { params(delegate: ICommand).void }
        def initialize(delegate)
          @delegate = delegate
          @actions = T.let([], T::Array[Action])
        end

        sig { override.params(requests: T::Array[Request]).returns(GenericResult) }
        def mark_requests_as_processing!(requests:)
          @actions << did_mark_requests_as_processing(requests:)
          @delegate.mark_requests_as_processing!(requests:)
        end

        sig { override.params(requests: T::Array[Request]).returns(GenericResult) }
        def delete_processing_requests!(requests:)
          @actions << did_delete_processing_requests(requests:)
          @delegate.delete_processing_requests!(requests:)
        end

        sig { override.params(requests: T::Array[Request::Eligible]).returns(ICommand::Result::UpdateRefs) }
        def update_refs!(requests:)
          @actions.concat(did_update_refs(requests:))
          @delegate.update_refs!(requests:)
        end

        sig { override.params(request: Request, reason: Enums::Failures).returns(GenericResult) }
        def dispatch_request_failure!(request:, reason:)
          @actions << did_dispatch_request_failure(request:, reason:)
          @delegate.dispatch_request_failure!(request:, reason:)
        end
      end
    end
  end
end
