# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    include Kernel
    extend T::Helpers

    MODELS = T.let([
      Copilot::Policies::Models::AChat,
      Copilot::Policies::Models::Af,
      Copilot::Policies::Models::Afos,
      Copilot::Policies::Models::Al,
      Copilot::Policies::Models::Aofo,
      Copilot::Policies::Models::GChat,
      Copilot::Policies::Models::Gtf,
      Copilot::Policies::Models::Gtff,
      Copilot::Policies::Models::GrokCode,
      Copilot::Policies::Models::O1,
      Copilot::Policies::Models::O3,
      Copilot::Policies::Models::Obmb,
      Copilot::Policies::Models::Obmw,
      Copilot::Policies::Models::Off,
      Copilot::Policies::Models::Ofm,
      Copilot::Policies::Models::Ofct,
      Copilot::Policies::Models::Ofo,
      Copilot::Policies::Models::Ot,
    ], T::Array[Copilot::Policy])

    ALL = T.let([
      Copilot::Policies::AgentMode,
      Copilot::Policies::AutomaticCodeReview,
      Copilot::Policies::Bing,
      Copilot::Policies::Cli,
      Copilot::Policies::CodeReview,
      Copilot::Policies::CodeReviewBetaFeatures,
      Copilot::Policies::CodingAgent,
      Copilot::Policies::CustomModels,
      Copilot::Policies::Desktop,
      Copilot::Policies::Dotcom,
      Copilot::Policies::DotcomBetaFeatures,
      Copilot::Policies::DotcomChat,
      Copilot::Policies::EaUserFallback,
      Copilot::Policies::EditorChat,
      Copilot::Policies::EditorPreviewFeatures,
      Copilot::Policies::Extensions,
      Copilot::Policies::Insights,
      Copilot::Policies::Mcp,
      Copilot::Policies::MetricsApi,
      Copilot::Policies::MobileChat,
      *MODELS,
      Copilot::Policies::PrSummarizations,
      Copilot::Policies::PrivateDocs,
      Copilot::Policies::PrivateTelemetry,
      Copilot::Policies::Snippy,
      Copilot::Policies::Spark,
      Copilot::Policies::UserFeedback,
      Copilot::Policies::WorkspaceForEmu
    ], T::Array[Copilot::Policy])

    ORG_MUTABLE = T.let(
        ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Organization::Mutable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Organization::Mutable)) }
        .index_by(&:config_name),
        T::Hash[Symbol, T.all(Copilot::Policy, Copilot::Policies::Concerns::Organization::Mutable)]
      )

    # only policies that implement the `Twirpable` concern
    TWIRPABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Twirpable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Twirpable)) },
      T::Array[T.all(Copilot::Policy, Copilot::Policies::Concerns::Twirpable)]
    )

    # only policies that implement the `User::Cacheable` concern
    CACHEABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::User::Cacheable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::User::Cacheable)) },
      T::Array[T.all(Copilot::Policy, Copilot::Policies::Concerns::User::Cacheable)]
    )

    # policies that implement the `Business::Propagatable` concern
    PROPAGATABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Business::Propagatable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Propagatable)) },
      T::Array[T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Propagatable)]
    )

    BUSINESS_MUTABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Business::Mutable) }
      .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Mutable)) }
      .index_by(&:config_name),
      T::Hash[Symbol, T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Mutable)]
    )

    # Instrumentation constants and methods

    # only policies that implement the `Instrumentable` concern
    INSTRUMENTABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Instrumentable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Instrumentable)) },
      T::Array[T.all(Copilot::Policy, Copilot::Policies::Concerns::Instrumentable)]
    )

    HIDDEN_FROM_AUDIT_LOG = T.let(INSTRUMENTABLE.select(&:hide_from_audit_log?).map(&:instrumentation_key), T::Array[Symbol])

    sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Hash[Symbol, Symbol]) }
    def self.instrumentation_hash(entity)
      all_policies = nil
      if entity.sorbet_class == ::User
        all_policies = T.cast(entity, Copilot::User).all_policies
      end

      INSTRUMENTABLE.each_with_object({}) do |policy, hash|
        instrumentation_value = policy.instrumentation_value(entity, all_policies)
        hash[policy.instrumentation_key] = instrumentation_value if instrumentation_value
      end
    end

    sig { params(user: Copilot::User).returns(T::Hash[Symbol, Integer]) }
    def self.twirp_user_settings(user)
      public_user = Copilot::Public::User.new(user.user_object)
      TWIRPABLE.each_with_object({}) do |policy, hash|
        twirp_value = policy.twirp_value(public_user)
        hash[policy.twirp_key] = twirp_value if twirp_value
      end
    end


  end
end
