# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class TagRule < RefUpdateRule
      include Bypasses

      def initialize
        super(rule_name: "tag",
              display_name: "Restrict pushes to protected tags")
      end

      # The tag policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        actor = context.actor
        repository = context.repository

        # Write deploy keys act as admins and can always push to protected tags
        # This must be special cased since the authorization check below will fail for them
        if actor.is_a?(PublicKey) && write_deploy_key?(repository, actor)
          return policies_by_ref_update.flat_map do |ref_update, rule_configs|
            rule_configs.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) }
          end
        end

        permission_actions = policies_by_ref_update.keys.map { |ref_update| permission_for_ref_update(ref_update) }.uniq.compact

        results = permission_actions.map do |permission_action|
          [permission_action, Platform::Loaders::Permissions::BatchAuthorize.load(
            action: permission_action,
            actor: actor,
            subject: repository,
          )]
        end.to_h

        resolved = results.keys.zip(Promise.all(results.values).sync).to_h
        policies_by_ref_update.flat_map do |ref_update, rule_configs|
          decision = resolved[permission_for_ref_update(ref_update)]
          if decision.nil?
            rule_configs.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) }
          else
            if decision.allow?
              rule_configs.map { |pc| RuleRun.success(rule_config: pc, ref_update: ref_update) }
            else
              denial_key = denial_reason_for_ref_update(ref_update)

              rule_configs.map do |pc|
                RuleRun.failure(rule_config: pc, ref_update: ref_update, evaluation_metadata: { reason_code: denial_key }, message: message(denial_key))
              end
            end
          end
        end
      end

      private

      def message(denial_key)
        case denial_key
        when :tag_changed
          "You're not authorized to change a protected tag"
        when :tag_deletion
          "You're not authorized to delete a protected tag"
        when :tag_creation
          "You're not authorized to create a tag"
        end
      end

      def permission_for_ref_update(ref_update)
        return unless ref_update.tag?

        if ref_update.creation?
          :create_tag
        elsif ref_update.deletion?
          :delete_tag
        else
          :change_tag
        end
      end

      def denial_reason_for_ref_update(ref_update)
        if ref_update.creation?
          :tag_creation
        elsif ref_update.deletion?
          :tag_deletion
        else
          :tag_changed
        end
      end
    end
  end
end
