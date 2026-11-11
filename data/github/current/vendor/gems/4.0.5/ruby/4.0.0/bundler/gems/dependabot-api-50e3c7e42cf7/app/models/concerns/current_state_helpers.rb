# typed: false
# frozen_string_literal: true

module CurrentStateHelpers
  extend T::Sig
  extend ActiveSupport::Concern

  included do
    scope :in_state, ->(*states) { where(current_state: states) }
    scope :not_in_state, ->(*states) { where.not(current_state: states) }

    def in_state?(*states)
      Array(states).map(&:to_s).include?(current_state)
    end
  end
end
