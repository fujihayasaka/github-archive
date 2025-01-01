# typed: strict
# frozen_string_literal: true

module GitHub
  class Diff
    sig do
      params(
        bk: T.proc.params(arg0: GitHub::Diff::Entry).returns(BasicObject),
      )
      .returns(T::Array[GitHub::Diff::Entry])
    end
    sig { returns(T::Enumerator[GitHub::Diff::Entry]) } # rubocop:disable Sorbet/EmptyLineAfterSig
    def each(&bk); end
  end
end
