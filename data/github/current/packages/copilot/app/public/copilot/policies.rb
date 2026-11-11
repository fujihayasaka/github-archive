# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    include Kernel
    extend T::Helpers

    # Register new models here
    # NOTE: These models are _in order_ of how they will appear in the organization settings UI.
    MODELS = T.let([
      Copilot::Policies::Models::Afos,
      Copilot::Policies::Models::Aofo,
      Copilot::Policies::Models::Lotus,
      Copilot::Policies::Models::Daisy,
      Copilot::Policies::Models::Bento,
      Copilot::Policies::Models::Gtf,
      Copilot::Policies::Models::Gtff,
      Copilot::Policies::Models::Tulip,
      Copilot::Policies::Models::Blueberry,
      Copilot::Policies::Models::O1,
      Copilot::Policies::Models::Off,
      Copilot::Policies::Models::Ofo,
      Copilot::Policies::Models::Obmb,
      Copilot::Policies::Models::Ofct,
      Copilot::Policies::Models::Obmw,
      Copilot::Policies::Models::Sunflower,
      Copilot::Policies::Models::MSpiderman,
      Copilot::Policies::Models::MThor,
      Copilot::Policies::Models::Arcticfox,
      Copilot::Policies::Models::Watermelon,
      Copilot::Policies::Models::Cucumber,
      Copilot::Policies::Models::Peony,
      Copilot::Policies::Models::GrokCode,
      # emergency models
      Copilot::Policies::Models::MIronman,
    ], T::Array[T.all(Copilot::Policy, Copilot::Policies::Concerns::Mutable)]) # models are all mutable

    ALL = T.let([
      Copilot::Policies::AgentMode,
      Copilot::Policies::AgentModeAutoApprove,
      Copilot::Policies::AutomaticCodeReview,
      Copilot::Policies::Bing,
      Copilot::Policies::CcrDirectOrgBilling,
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
      Copilot::Policies::GeneratedCommitMessage,
      Copilot::Policies::Insights,
      Copilot::Policies::Loops,
      Copilot::Policies::Mcp,
      Copilot::Policies::MetricsApi,
      Copilot::Policies::MobileChat,
      *MODELS,
      Copilot::Policies::PrSummarizations,
      Copilot::Policies::PrivateDocs,
      Copilot::Policies::PrivateTelemetry,
      Copilot::Policies::RestrictToAzure,
      Copilot::Policies::Snippy,
      Copilot::Policies::Spaces,
      Copilot::Policies::SpacesIndividualAccess,
      Copilot::Policies::SpacesIndividualSharing,
      Copilot::Policies::Spark,
      Copilot::Policies::SparkForceOrg,
      Copilot::Policies::UserFeedback,
      Copilot::Policies::WorkspaceForEmu
    ], T::Array[Copilot::Policy])

    USER_MUTABLE = T.let(
        ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::User::Mutable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::User::Mutable)) }
        .index_by(&:config_name),
        T::Hash[Symbol, T.all(Copilot::Policy, Copilot::Policies::Concerns::User::Mutable)]
    )

    ORG_MUTABLE = T.let(
        ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Organization::Mutable) }
        .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Organization::Mutable)) }
        .index_by(&:config_name),
        T::Hash[Symbol, T.all(Copilot::Policy, Copilot::Policies::Concerns::Organization::Mutable)]
    )

    BUSINESS_MUTABLE = T.let(
      ALL.select { |p| p.is_a?(Copilot::Policies::Concerns::Business::Mutable) }
      .map { |p| T.cast(p, T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Mutable)) }
      .index_by(&:config_name),
      T::Hash[Symbol, T.all(Copilot::Policy, Copilot::Policies::Concerns::Business::Mutable)]
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
      old_policy_collation = TWIRPABLE.each_with_object({}) do |policy, hash|
        twirp_value = policy.twirp_value(public_user, user)
        hash[policy.twirp_key] = twirp_value
      end

      if public_user.model_policies.present? && FeatureFlag.vexi.enabled?("simple-simship-static-registry-step", user, default: false)
        new_policy_collation = {}
        Copilot::ModelsRegistryCache.all.each do |model|
          model_key = model.model_key.to_sym
          db_value = public_user.model_policies[model_key] || "unconfigured"
          twirp_value = case db_value
          when "enabled"
            MonolithTwirp::Copilot::Users::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_ENABLED_SETTING
          when "disabled"
            MonolithTwirp::Copilot::Users::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_DISABLED_SETTING
          when "unconfigured"
            MonolithTwirp::Copilot::Users::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_UNCONFIGURED_SETTING
          when "no_policy"
            MonolithTwirp::Copilot::Users::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_NO_POLICY_SETTING
          else
            MonolithTwirp::Copilot::Users::V1::ModelPolicyConfiguration::MODEL_POLICY_CONFIGURATION_INVALID
          end

          new_policy_collation[model_key] = twirp_value
        end

        return old_policy_collation.merge(model_policies: { model_policy: new_policy_collation }) if new_policy_collation.present?
      end

      old_policy_collation
    end

    sig { params(entity: Copilot::Types::CopilotEntity).returns(T::Hash[Symbol, Symbol]) }
    def self.configuration_defaults(entity)
      Copilot::Policies::ALL.each_with_object({}) do |policy, hash|
        hash[policy.config_name.to_sym] = policy.default_value(entity).to_sym
      end
    end

    class PolicyDescriptionChunk < T::Struct
      const :text, String
      const :href, T.nilable(String)
    end

    PolicyDescription = T.type_alias { T::Array[T.any(PolicyDescriptionChunk, String)] }
  end
end
