# typed: true
# frozen_string_literal: true

class TestCustomPropertyDefinition
  extend GeneratedRelationMethods

  sig { returns(T.untyped) }
  def source; end

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::CustomPropertyDefinition } }

    sig { returns(T::Array[::CustomPropertyDefinition]) }
    def to_a; end

    sig { returns(T::Array[::CustomPropertyDefinition]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def defined_by(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_organization_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_property_name_like(*args, &blk); end
  end
end

class TestCustomPropertyValue
  extend GeneratedRelationMethods

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestCustomPropertyValue } }

    sig { returns(T::Array[::TestCustomPropertyValue]) }
    def to_a; end

    sig { returns(T::Array[::TestCustomPropertyValue]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_matching_value_strings(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def with_property_value_like(*args, &blk); end
  end
end

class TestSystemPropertyValue
  extend GeneratedRelationMethods

  class << self
    sig { returns(T::Hash[T.any(String, Symbol), Integer]) }
    def definition_ids; end
  end

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestSystemPropertyValue } }

    sig { returns(T::Array[::TestSystemPropertyValue]) }
    def to_a; end

    sig { returns(T::Array[::TestSystemPropertyValue]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_matching_value_strings(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def with_property_value_like(*args, &blk); end
  end
end

class TestCustomPropertyUsage
  extend GeneratedRelationMethods

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestCustomPropertyUsage } }

    sig { returns(T::Array[::TestCustomPropertyUsage]) }
    def to_a; end

    sig { returns(T::Array[::TestCustomPropertyUsage]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_resource(*args, &blk); end
  end
end
