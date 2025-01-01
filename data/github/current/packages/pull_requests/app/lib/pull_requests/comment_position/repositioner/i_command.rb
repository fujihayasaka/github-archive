# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Interface describing side effects performed by the Processor. This enables us to inject dependencies such as git
      # and the database.
      module ICommand
        extend T::Helpers

        interface!
        CommandFailed = Class.new(StandardError)

        module Result
          extend T::Helpers
          sealed!

          # Call the block up until max_attempts number of times. Retrying only occurs when the Error object returned
          # permits retrying.
          sig do
            type_parameters(:T).params(
              max_attempts: Integer,
              block: T.proc.returns(T.type_parameter(:T))
            ).returns(T.type_parameter(:T))
          end
          def self.with_retry(max_attempts = 3, &block)
            yield
          end

          class Success
            include Result
          end

          # Generic "error" type return value. This is to deal with unknown/uncaught exceptions and are generally
          # only able to be reported. Concrete errors with known handling should be their own class, like CreateCommitSuccess.
          class Error < T::Struct
            include Result
            include PullRequests::MergeCommit::Errors

            const :message, String
            const :permit_retry, T::Boolean, default: false
            const :exception, T.nilable(Exception), default: nil

            sig { returns(CommandFailed) }
            def as_exception
              domain_exception = CommandFailed.new(message)

              if exception.nil?
                domain_exception
              else
                wrap_exception_with(domain_exception)
              end
            end

            private

            sig { params(wrapper: CommandFailed).returns(CommandFailed) }
            def wrap_exception_with(wrapper)
              # The only way to set the `cause` field on an exception is to raise
              # it from a rescue block. In this case, we want to set our exception
              # as the cause of a `CommandFailed` instance.
              begin
                raise T.must(exception)
              rescue # rubocop:todo Lint/GenericRescue
                raise wrapper
              end
            rescue CommandFailed => result
              result
            end
          end
        end

        GenericResult = T.type_alias { T.any(Result::Success, Result::Error) }
      end
    end
  end
end
