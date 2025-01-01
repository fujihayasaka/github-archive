# typed: strict
# frozen_string_literal: true

# rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
# rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class FeatureFlag
      sig { params(feature_flag: T.any(String, Symbol), actor: T.nilable(T.all(Vexi::Actor, GitHub::IFlipperActor)), diagnostic_io:  T.any(StringIO, IO)).void }
      def self.enable(feature_flag:, actor: nil, diagnostic_io: $stdout)
        if actor.nil?
          ::FeatureFlag.vexi_management.enable_feature_flag(feature_flag)
        else
          ::FeatureFlag.vexi_management.add_feature_flag_actors(feature_flag, [actor])
        end
      end

      sig { params(feature_flag: T.any(String, Symbol), actor: T.nilable(T.all(Vexi::Actor, GitHub::IFlipperActor)), diagnostic_io:  T.any(StringIO, IO)).void }
      def self.disable(feature_flag:, actor: nil, diagnostic_io: $stdout)
        if actor.nil?
          ::FeatureFlag.vexi_management.disable_feature_flag(feature_flag)
        else
          ::FeatureFlag.vexi_management.remove_feature_flag_actors(feature_flag, [actor])
        end
      end

      sig { params(feature_flag: T.any(String, Symbol), diagnostic_io: T.any(StringIO, IO)).void }
      def self.ensure_feature_flag_exists(feature_flag, diagnostic_io = $stdout)
        unless ::FeatureFlag.vexi.exists_or_raise?(feature_flag)
          ::FeatureFlag.vexi_management.disable_feature_flag(feature_flag)
        end
      end
    end
  end
end

# rubocop:enable GitHub/FeatureManagement/NoVexiManagementUsage
# rubocop:enable GitHub/FeatureManagement/NoVexiNonStandardUsage
