# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  module Public

    sig do
      params(
        attributes: T::Hash[Symbol, T.untyped],
        operation: Codespaces::AsyncOperation,
        stats_tagger: CloudEnvironments::IStatsTagger,
        environment_options: T::Hash[Symbol, T.untyped],
        entry_point: T.nilable(T.any(String, Symbol))
      ).returns(ICreateResult)
    end
    def self.create(
      attributes:,
      operation:,
      stats_tagger:,
      environment_options:,
      entry_point:
    )
      Create.new(
        attributes:,
        operation:,
        stats_tagger:,
        environment_options:,
        entry_point:
      ).perform
    end

    def self.create_ephemeral(
      attributes:,
      operation:,
      stats_tagger:,
      environment_options:,
      entry_point:
    )
      attributes[:copilot_workspace_id] = Codespace::EPHEMERAL_CLOUDSPACE_ID
      Create.new(
        attributes:,
        operation:,
        stats_tagger:,
        environment_options:,
        entry_point:
      ).perform
    end

    sig do
      params(id: Integer).returns(CloudEnvironments::ICloudEnvironment)
    end
    def self.by_id(id)
      T.cast(CloudEnvironments::CloudEnvironment.find_by(id:), CloudEnvironments::ICloudEnvironment)
    end

    sig do
      params(ids: T::Array[Integer]).returns(T::Array[CloudEnvironments::ICloudEnvironment])
    end
    def self.by_ids(ids)
      T.cast(CloudEnvironments::CloudEnvironment.where(id: ids).to_a, T::Array[CloudEnvironments::ICloudEnvironment])
    end
  end
end
