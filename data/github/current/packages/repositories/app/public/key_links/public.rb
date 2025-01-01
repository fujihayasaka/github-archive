# typed: strict
# frozen_string_literal: true

module KeyLinks
  module Public
    extend self

    include Kernel

    URL_NUMBER_TEMPLATE = T.let("<num>", String)

    # remove this method when we remove key_links_methods FF
    sig { params(owner: ::Repository).returns(T::Boolean) }
    def custom_key_links_active_for?(owner)
      GitHub::Result.new { owner.custom_key_links_active? }.value { false }
    end

    # remove this method when we remove key_links_methods FF
    sig { params(owner: ::Repository).returns(T.nilable(String)) }
    def key_links_cache_key_for(owner)
      GitHub::Result.new { owner.key_links_cache_key }.value { nil }
    end

    extend GitHub::DomainIsolation::PackageBoundary
  end
end
