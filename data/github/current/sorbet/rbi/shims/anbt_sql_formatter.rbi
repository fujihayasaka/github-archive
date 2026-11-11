# typed: true

module AnbtSql
  class Rule
    extend T::Sig

    KEYWORD_UPPER_CASE = T.let(nil, T.untyped)

    sig { void }
    def initialize; end

    sig { returns(T.untyped) }
    def keyword; end

    sig { params(value: T.untyped).returns(T.untyped) }
    def keyword=(value); end

    sig { returns(T::Boolean) }
    def space_after_comma; end

    sig { params(value: T::Boolean).returns(T::Boolean) }
    def space_after_comma=(value); end

    sig { returns(String) }
    def indent_string; end

    sig { params(value: String).returns(String) }
    def indent_string=(value); end
  end

  class Formatter
    extend T::Sig

    sig { params(rule: Rule).void }
    def initialize(rule); end

    sig { params(sql: String).returns(String) }
    def format(sql); end
  end
end
