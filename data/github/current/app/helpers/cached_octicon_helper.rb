# typed: true
# frozen_string_literal: true

module CachedOcticonHelper
  extend T::Helpers

  requires_ancestor { ActionView::Base }

  class CachedOcticonComponent < Primer::Beta::Octicon
    include ApplicationComponent::Cacheable
  end

  def primer_octicon(*args, **kwargs, &block)
    if primer_octicon_cache_enabled?
      render CachedOcticonComponent.with(*T.unsafe(args), **T.unsafe(kwargs), &block)
    else
      render Primer::Beta::Octicon.new(*T.unsafe(args), **T.unsafe(kwargs)), &block
    end
  rescue RuntimeError => error
    Failbot.report error

    nil
  end

  private

  def primer_octicon_cache_enabled?
    return @_primer_octicon_cache_enabled if defined?(@_primer_octicon_cache_enabled)
    @_primer_octicon_cache_enabled = GitHub.flipper["primer_octicon_cache"].enabled?
  end
end
