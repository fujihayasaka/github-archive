# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PageCertificateState < Platform::Enums::Base
      description "The possible page certificate states."
      visibility :internal

      ::Page::Certificate.states.each_key do |state|
        value state.upcase, ::Page::Certificate.state_description(state), value: state.to_sym
      end
    end
  end
end
