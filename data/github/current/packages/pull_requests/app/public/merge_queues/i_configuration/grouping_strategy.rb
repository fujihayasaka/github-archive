# typed: strict
# frozen_string_literal: true

module MergeQueues
  module IConfiguration
    class GroupingStrategy < T::Enum
      sig { override(allow_incompatible: true).params(value: T.nilable((T.any(Symbol, String)))).returns(GroupingStrategy) } # rubocop:disable Sorbet/AllowIncompatibleOverride
      def self.deserialize(value)
        case value
        when :ALLGREEN then AllGreen
        when :HEADGREEN then HeadGreen
        when "", nil, :"" then MergeQueues.default_configuration.grouping_strategy
        when String then deserialize(value.to_sym)
        else
          super
        end
      rescue KeyError => exception
        Failbot.report(exception)
        MergeQueues.default_configuration.grouping_strategy
      end

      sig { params(value: T.nilable(GroupingStrategy)).returns(T.nilable(String)) }
      def self.description(value)
        case value
        when AllGreen
          "The merge commit created by merge queue for each PR in the group must pass all required checks to merge"
        when HeadGreen
          "Only the commit at the head of the merge group must pass its required checks to merge."
        end
      end

      enums do
        AllGreen = new("ALLGREEN")
        HeadGreen = new("HEADGREEN")
      end
    end
  end
end
