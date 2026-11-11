# typed: true
# frozen_string_literal: true

class TestExternalPropertyNamespace
  extend GeneratedRelationMethods

  sig { returns(T.untyped) }
  def source; end

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestExternalPropertyNamespace } }

    sig { returns(T::Array[::TestExternalPropertyNamespace]) }
    def to_a; end

    sig { returns(T::Array[::TestExternalPropertyNamespace]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def defined_by(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_source(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_business_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_org_ids(*args, &blk); end
  end
end

class TestExternalPropertyDefinition
  extend GeneratedRelationMethods

  sig { returns(T.untyped) }
  def source; end

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestExternalPropertyDefinition } }

    sig { returns(T::Array[::TestExternalPropertyDefinition]) }
    def to_a; end

    sig { returns(T::Array[::TestExternalPropertyDefinition]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_namespace(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_namespace_ids(*args, &blk); end
  end
end

class TestExternalPropertyValue
  extend GeneratedRelationMethods

  class PrivateRelation < ::ActiveRecord::Relation
    Elem = type_member { { fixed: ::TestExternalPropertyValue } }

    sig { returns(T::Array[::TestExternalPropertyValue]) }
    def to_a; end

    sig { returns(T::Array[::TestExternalPropertyValue]) }
    def to_ary; end
  end

  module GeneratedRelationMethods
    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_target_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_definition_ids(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def for_matching_value_strings(*args, &blk); end

    sig { params(args: T.untyped, blk: T.untyped).returns(PrivateRelation) }
    def with_property_value_like(*args, &blk); end
  end
end
