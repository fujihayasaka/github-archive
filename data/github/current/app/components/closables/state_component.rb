# typed: strict
# frozen_string_literal: true

module Closables
  class StateComponent < Closables::BaseComponent
    extend T::Sig

    sig { params(closable: Closable, size: Symbol, system_arguments: T.untyped).void }
    def initialize(closable:, size: Primer::Beta::State::SIZE_DEFAULT, **system_arguments)
      @closable         = closable
      @size             = size
      @system_arguments = system_arguments
    end

    private

    sig { returns(Symbol) }
    attr_reader :size

    sig { returns(T::Boolean) }
    def render?
      # We don't want to display the open state badge for discussions
      !closable.is_a?(Discussion) || closable.closed?
    end

    sig { returns(String) }
    def state
      closable.closed? ? "Closed" : "Open"
    end

    sig { returns(Symbol) }
    def scheme
      reason = current_reason
      reason.present? ? reason.badge_scheme : :open
    end

    sig { returns(Symbol) }
    def octicon_size
      size == :small ? :xsmall : :small
    end

    sig { returns(Symbol) }
    def octicon
      reason = current_reason
      reason.present? ? reason.octicon : :"issue-opened"
    end

    sig { returns(String) }
    def title
      reason = current_reason
      title_text = reason.present? ? reason.badge_title : state
      "Status: #{title_text}"
    end
  end
end
