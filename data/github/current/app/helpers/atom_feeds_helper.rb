# typed: true
# frozen_string_literal: true

module AtomFeedsHelper
  include Kernel

  ATOM_CONTENT_TYPES = ["atom", "application/atom+xml"].freeze

  sig { returns(T::Boolean) }
  def atom_feed?
    return @_is_atom_feed if defined?(@_is_atom_feed)

    # No request/response when coming from MentionFilter in HTML pipeline
    # T.unsafe(self) is needed to bypass Sorbet's static checking since these methods are dynamically provided by Rails.
    is_atom_request = respond_to?(:request) && T.unsafe(self).request && T.unsafe(self).request.format.atom?
    is_atom_response = respond_to?(:response) && T.unsafe(self).response &&
      ATOM_CONTENT_TYPES.include?(T.unsafe(self).response.media_type)
    @_is_atom_feed = !!(is_atom_request || is_atom_response)
  end
end
