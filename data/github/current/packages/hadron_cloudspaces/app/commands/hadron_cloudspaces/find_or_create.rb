# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  class FindOrCreate < CloudEnvironments::Command

    class Result
      include IFindOrCreateResult
      include GitHub::Memoizer
      extend T::Sig

      sig { params(hadron_cloudspace: HadronCloudspace).returns(HadronCloudspace) }
      attr_writer :hadron_cloudspace

      sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
      attr_writer :env

      sig { params(found: T::Boolean).returns(T::Boolean) }
      attr_writer :found

      sig { override.returns(T.nilable(HadronCloudspace)) }
      attr_reader :hadron_cloudspace

      sig { override.returns(T.nilable(Codespaces::Environment)) }
      attr_reader :env

      sig { override.returns(T::Boolean) }
      def found?
        !!@found
      end
    end

    class HadronFeatureDisabledError < StandardError
      include HadronCloudspaces::IFeatureDisabledError
    end

    extend T::Sig
    include ActiveModel::Validations

    attr_reader :owner, :repository_id, :pull_request_number, :location, :display_name, :devcontainer_path, :sku_name, :vscs_target_url, :result, :ref, :oid, :operation, :entry_point

    sig do
      params(
        owner: User,
        repository_id: Integer,
        pull_request_number: Integer,
        operation: Codespaces::AsyncOperation,
        location: String,
        display_name: T.nilable(String),
        devcontainer_path: T.nilable(String),
        sku_name: T.nilable(String),
        vscs_target: T.nilable(String),
        vscs_target_url: T.nilable(String),
        concurrency_policy: T.nilable(T.class_of(CloudEnvironments::IConcurrencyLimiter)),
        entry_point: T.nilable(String),
      ).void
    end
    def initialize(
        owner:,
        repository_id:,
        pull_request_number:,
        operation:,
        location:,
        display_name: nil,
        devcontainer_path: nil,
        sku_name: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        concurrency_policy: nil,
        entry_point: nil
      )
      @owner = owner
      @repository_id = repository_id
      @pull_request_number = pull_request_number
      @operation = operation
      @location = location
      @display_name = display_name
      @devcontainer_path = devcontainer_path.presence
      @sku_name = sku_name.presence
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
      @result = Result.new
      @concurrency_policy = concurrency_policy
      @entry_point = entry_point
    end

    # Note: Validations are handled in the respective Find and Create commands
    def perform
      found_result = Find.call(
        owner:,
        repository_id:,
        pull_request_number:,
        operation:,
        location:,
        devcontainer_path:,
        sku_name:,
        vscs_target: @vscs_target,
        vscs_target_url:,
        entry_point:,
        connect: true,
      )

      if found_result.hadron_cloudspace.present?
        @result.hadron_cloudspace = found_result.hadron_cloudspace
        @result.env = found_result.env if found_result.env.present?
        @result.found = true
      else
        create_result = Create.call(
          owner:,
          repository_id:,
          pull_request_number:,
          operation:,
          location:,
          display_name:,
          devcontainer_path:,
          sku_name:,
          vscs_target: @vscs_target,
          vscs_target_url:,
          entry_point:,
        )
        @result.hadron_cloudspace = create_result.hadron_cloudspace
        @result.env = create_result.env if create_result.env.present?
        @result.found = false
      end

      @result
    end
  end
end
