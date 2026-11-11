# typed: strict
# frozen_string_literal: true

module Issues
  module IPlanningTemplate

    class TemplateType < T::Enum
      enums do
        DEFAULT = new(:default)
        CUSTOM = new(:custom)
      end
    end

    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(Integer)) }
    def owner_id; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def description; end

    sig { abstract.returns(User) }
    def owner; end

    sig { abstract.returns(TemplateType) }
    def template_type; end
  end
end
