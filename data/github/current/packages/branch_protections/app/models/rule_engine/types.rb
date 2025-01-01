# typed: true
# frozen_string_literal: true

module RuleEngine
  class Types
    # Types that can be an actor for rules
    Actor = T.type_alias { T.any(User, Bot, PublicKey) }

    # Types that can be a source for rules
    RuleSource = T.type_alias { T.any(Repository, Organization, Business) }

    # Git::Ref::Update::Null is used for ref updates with no defined after_oid
    NullableRefUpdate = T.type_alias { T.any(Git::Ref::Update, Git::Ref::Update::Null) }

    # Determines which rules are evaluated
    class Phase < T::Enum
      enums do
        #Only evaluates rules targeting push
        PreReceive = new

        # Only evaluates rules targeting branch or tag
        PostReceive = new
      end
    end
  end
end
