# typed: strict
# frozen_string_literal: true

module Loops
  module AccessVerifiers
    # Verifies global relay ID access using Platform::Helpers::NodeIdentification
    # This is the recommended approach as it follows GitHub's standard patterns
    class PlatformPermissionChecker
      include GitHub::Memoizer

      # Simple wrapper for failed promise creation
      class FailedPromise
        sig { params(error: StandardError).void }
        def initialize(error)
          @error = error
        end

        sig { returns(T.noreturn) }
        def sync
          raise @error
        end
      end

      # Result object for access verification
      class VerificationResult < T::Struct
        const :id, String
        const :accessible, T::Boolean
        const :error, T.nilable(String)
      end

      # Batch result object
      class BatchResult < T::Struct
        const :results, T::Hash[String, T::Boolean]
        const :errors, T::Hash[String, String]
        const :total_checked, Integer
        const :accessible_count, Integer
        const :denied_count, Integer
      end

      sig { params(token: String, remote_ip: T.nilable(String)).void }
      def initialize(token:, remote_ip: nil)
        @token = token
        @remote_ip = remote_ip
      end

      # Verify access to a batch of global relay IDs
      # @param resources [Hash<String, String>] Map of global_relay_id => typename
      # @return [BatchResult] Results of the verification
      sig { params(resources: T::Hash[String, String]).returns(BatchResult) }
      def verify_batch(resources)
        permission = create_permission

        Platform::Security::RepositoryAccess.with_viewer(user) do
          promise_data = resources.map do |global_relay_id, expected_typename|
            {
              global_relay_id: global_relay_id,
              expected_typename: expected_typename,
              promise: create_object_promise(global_relay_id, permission)
            }
          end

          # Now resolve all promises and process results
          verification_results = promise_data.map do |data|
            process_promise_result(data[:global_relay_id], data[:promise])
          end

          build_batch_result(verification_results)
        end
      end

      sig { returns(GitHub::Authentication::Result) }
      memoize def authentication
        GitHub::Authentication::Attempt.new(
          token:                              @token,
          ip:                                 @remote_ip,
          from:                               :loops,
          allow_integrations:                 false,
          allow_user_via_granular_actor:      true,
          password_auth_blocked:              true
        ).result
      end

      sig { returns(T.nilable(User)) }
      def user
        authentication.user
      end

      sig { returns(String) }
      attr_reader :token

      private

      sig { returns(Platform::Authorization::Permission) }
      def create_permission
        context = {
          token: @token,
          ip: @remote_ip,
          origin: Platform::ORIGIN_API,
          viewer: user
        }

        Platform::Authorization::Permission.new(context)
      end

      sig { params(results: T::Array[VerificationResult]).returns(BatchResult) }
      def build_batch_result(results)
        verification_map = {}
        error_map = {}
        accessible_count = 0

        results.each do |result|
          verification_map[result.id] = result.accessible
          error_map[result.id] = result.error if result.error
          accessible_count += 1 if result.accessible
        end

        BatchResult.new(
          results: verification_map,
          errors: error_map,
          total_checked: results.length,
          accessible_count: accessible_count,
          denied_count: results.length - accessible_count
        )
      end

      # Create a promise for object lookup without resolving it
      sig { params(global_relay_id: String, permission: Platform::Authorization::Permission).returns(T.untyped) }
      def create_object_promise(global_relay_id, permission)
        begin
          # rubocop:disable GitHub/UntypedObjectId
          # We need untyped here because this helper can verify any object type
          Platform::Helpers::NodeIdentification.untyped_object_from_id(
            global_relay_id,
            permission: permission,
            target: :public
          )
          # rubocop:enable GitHub/UntypedObjectId
        rescue StandardError => e
          # Return a "failed promise" object that we can handle consistently
          FailedPromise.new(e)
        end
      end

      # Process a resolved promise and return verification result
      sig do
        params(
          global_relay_id: String,
          promise: T.untyped
        ).returns(VerificationResult)
      end
      def process_promise_result(global_relay_id, promise)
        begin
          object = promise.sync

          VerificationResult.new(
            id: global_relay_id,
            accessible: true,
            error: nil
          )

        rescue Platform::Errors::NotFound => e
          VerificationResult.new(
            id: global_relay_id,
            accessible: false,
            error: "Not found: #{e.message}"
          )
        rescue Platform::Errors::Forbidden => e
          VerificationResult.new(
            id: global_relay_id,
            accessible: false,
            error: "Forbidden: #{e.message}"
          )
        rescue StandardError => e
          VerificationResult.new(
            id: global_relay_id,
            accessible: false,
            error: "Error: #{e.message}"
          )
        end
      end
    end
  end
end
