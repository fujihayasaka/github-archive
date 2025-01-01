# typed: strict
# frozen_string_literal: true

module CustomProperties
  module IPropertyUsage
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(String) }
    def property_name; end

    sig { abstract.returns(String) }
    def property_value; end

    sig { abstract.returns(String) }
    def consumer_type; end

    sig { abstract.returns(String) }
    def consumer_id; end
  end
end
