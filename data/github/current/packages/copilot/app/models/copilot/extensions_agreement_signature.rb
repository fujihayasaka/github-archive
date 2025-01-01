# typed: strict
# frozen_string_literal: true

module Copilot
  class ExtensionsAgreementSignature < ApplicationRecord::Copilot
    include ::Instrumentation::Model

    self.table_name = "copilot_extensions_agreement_signatures"
    self.strict_loading_by_default = true

    belongs_to :signatory, class_name: "::User", strict_loading: false
    belongs_to :organization, class_name: "::Organization", strict_loading: false
    belongs_to :business, class_name: "::Business", strict_loading: false

    validates :signatory, presence: true

    sig do
      params(signatory: ::User, context: T.nilable(T.any(::User, ::Organization, ::Business)))
        .returns(Copilot::ExtensionsAgreementSignature)
    end
    def self.sign!(signatory:, context: nil)
      case context
      when ::Business
        create!(signatory: signatory, business: context)
      when ::Organization
        create!(signatory: signatory, organization: context)
      else
        create!(signatory: signatory)
      end
    end

    sig { params(context: T.any(::User, ::Organization, ::Business)).returns(T::Boolean) }
    def self.signed_by?(context)
      case context
      when ::Business
        Copilot::ExtensionsAgreementSignature.exists?(business: context)
      when ::Organization
        Copilot::ExtensionsAgreementSignature.exists?(organization: context)
      else
        Copilot::ExtensionsAgreementSignature.exists?(signatory: context)
      end
    end
  end
end
