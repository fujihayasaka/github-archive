# typed: strict
# frozen_string_literal: true

module Billing::Settings
  class BillingInformationConfirmDereferenceComponent < ApplicationComponent
    sig { returns(User) }
    attr_reader :actor
    sig { returns(Organization) }
    attr_reader :target
    sig { returns(T.nilable(String)) }
    attr_reader :return_to
    sig { returns(T::Boolean) }
    attr_reader :include_form_tag

    sig { params(actor: User, target: Organization, return_to: T.nilable(String), include_form_tag: T::Boolean).void }
    def initialize(actor:, target:, return_to: nil, include_form_tag: true)
      @actor = actor
      @target = target
      @return_to = return_to
      @include_form_tag = include_form_tag
    end

    sig { returns(T::Boolean) }
    def render?
      target.org_is_on_standard_tos?
    end

    sig { returns(T::Boolean) }
    def include_form_tag?
      @include_form_tag
    end

    sig { params(url_for: T.nilable(String), method: Symbol, block: T.proc.returns(T.untyped)).returns(T.any(String, T.untyped)) }
    def render_billing_info_inputs(url_for: nil, method: :put, &block)
      if include_form_tag?
        form_tag(url_for, method: method, &block)
      else
        capture(&block)
      end
    end
  end
end
