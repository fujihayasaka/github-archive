# typed: strict
# frozen_string_literal: true

module Copilot
  class Plans
    class CFI < T::Enum
      enums do
        # This is for Copilot Free (otherwise known as limited users)
        # not to be confused with Copilot Pro for Free
        Free = new("free")
        Pro = new("pro")
        ProPlus = new("pro_plus")
        Max = new("max")
      end

      # need to accept CFB and CFI plans for users which may have either
      sig { params(plan: T.nilable(Copilot::Plan)).returns(T::Boolean) }
      def at_least?(plan)
        return false if plan.nil? || plan.is_a?(CFB)

        tier >= plan.tier
      end

      protected

      sig { returns(Integer) }
      def tier
        case self
        when Free then 1
        when Pro then 2
        when ProPlus then 3
        when Max then 4
        else
          T.absurd(self)
        end
      end
    end

    class CFB < T::Enum
      enums do
        # Business tier will never be returned, but makes it easy to specify at least _any_ business plan
        Business = new("business")
        StandaloneBusiness = new("standalone_business")
        NonStandaloneBusiness = new("non_standalone_business")
        Enterprise = new("enterprise")
      end

      # need to accept CFB and CFI plans for users which may have either
      sig { params(plan: T.nilable(Copilot::Plan)).returns(T::Boolean) }
      def at_least?(plan)
        return false if plan.nil? || plan.is_a?(CFI)

        tier >= plan.tier
      end

      protected

      sig { returns(Integer) }
      def tier
        case self
        when Business then 1
        when StandaloneBusiness then 2
        when NonStandaloneBusiness then 3
        when Enterprise then 4
        else
          T.absurd(self)
        end
      end
    end
  end
end
