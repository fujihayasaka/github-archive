# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module IPropertyTarget
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(T.nilable(Integer)) }
    def properties_target_id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def properties_org_source_id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def properties_business_source_id; end
  end
end
