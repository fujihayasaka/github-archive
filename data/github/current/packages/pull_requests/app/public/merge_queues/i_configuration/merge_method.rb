# typed: strict
# frozen_string_literal: true

module MergeQueues
  module IConfiguration
    class MergeMethod < T::Enum
      sig { override(allow_incompatible: true).params(value: T.nilable((T.any(Symbol, String)))).returns(MergeMethod) } # rubocop:disable Sorbet/AllowIncompatibleOverride
      def self.deserialize(value)
        case value
        when :merge then Merge
        when :rebase then Rebase
        when :squash then Squash
        when "", nil, :"" then MergeQueues.default_configuration.merge_method
        when String then deserialize(value.to_sym)
        else
          super
        end
      rescue KeyError => exception
        Failbot.report(exception)
        MergeQueues.default_configuration.merge_method
      end

      enums do
        Merge = new(:merge)
        Squash = new(:squash)
        Rebase = new(:rebase)
      end
    end
  end
end
