# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class Group
        extend T::Sig
        extend T::Helpers
        abstract!

        sig { returns(::Organization) }; attr_reader :scope
        sig { returns(::User) }; attr_reader :user
        sig { returns(String) }; attr_reader :group_key

        sig { params(scope: ::Organization, user: ::User, group_key: String).void }
        def initialize(scope:, user:, group_key:)
          @scope = scope
          @user = user
          @group_key = group_key
        end

        sig do
          abstract.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature); end

        sig do
          overridable
            .params(items: T::Array[GroupDataQuery::AlertGroupData])
            .returns(T::Array[GroupDataQuery::AlertGroupData])
        end
        def finalize(items)
          # Default implementation is a noop - subclasses may implement custom logic
          items
        end
      end
    end
  end
end
