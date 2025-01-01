# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::AgreementEditorComponent < ApplicationComponent
  extend T::Sig

  sig { params(agreement: SponsorsAgreement).void }
  def initialize(agreement:)
    @agreement = agreement
  end

  private

  sig { returns(SponsorsAgreement) }
  attr_reader :agreement

  sig { returns(T::Boolean) }
  def render?
    GitHub.sponsors_enabled? && logged_in?
  end

  sig { returns(T::Array[T::Array[T.any(String, Symbol)]]) }
  def agreement_kind_select_options
    SponsorsAgreement::AGREEMENT_NAMES_BY_KIND.sort_by { |_kind, name| name.downcase }.to_h.invert.to_a
  end
end
