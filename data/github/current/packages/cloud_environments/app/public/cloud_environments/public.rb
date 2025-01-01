# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  module Public
    extend T::Sig

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
  end
end
