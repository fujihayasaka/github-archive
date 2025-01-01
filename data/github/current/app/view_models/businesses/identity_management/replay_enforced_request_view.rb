# typed: true
# frozen_string_literal: true

module Businesses::IdentityManagement
  class ReplayEnforcedRequestView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :business, :form_data

    def form_target
      @target ||= form_data.delete("_target")
    end

    def form_method
      @method ||= (form_data.delete("_method") || :post).to_sym
    end
  end
end
