# typed: strict
# frozen_string_literal: true

module Billing
  module ICoupon
    extend T::Helpers

    include Kernel

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns(String) }
    def code; end

    sig { abstract.returns(Integer) }
    def discount; end

    sig { abstract.returns(String) }
    def group; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def expires_at; end

    sig { abstract.returns(String) }
    def note; end

    sig { abstract.returns(Integer) }
    def limit; end

    sig { abstract.returns(Integer) }
    def duration; end

    sig { abstract.returns(T::Boolean) }
    def ghec_only_group?; end

    sig { abstract.returns(String) }
    def product_type; end

    sig { abstract.returns(T.nilable(String)) }
    def product_key; end

    sig { abstract.returns(T.nilable(String)) }
    def product_target_name; end

    sig { abstract.returns(T::Boolean) }
    def has_product_target?; end

    sig { abstract.returns(T.nilable(GitHub::Plan)) }
    def plan; end

    sig { abstract.returns(T::Boolean) }
    def plan_specific?; end
  end
end
