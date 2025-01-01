# typed: true
# frozen_string_literal: true

module Repository::CustomKeyLinksDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_many :key_links, as: :owner
  end

  def has_key_links?
    return @_has_key_links if defined?(@_has_key_links)
    @_has_key_links = key_links.any?
  end

  def custom_key_links_active?
    return @_custom_key_links_active if defined?(@_custom_key_links_active)

    # call has_key_links? first to avoid an expensive plan_supports? check if there are no key_links
    @_custom_key_links_active = has_key_links? && plan_supports?(:custom_key_links)
  end

  def key_links_cache_key
    return @_key_links_cache_key if defined?(@_key_links_cache_key)

    # key_links cannot be edited, only created and deleted, so using just the IDs should be sufficient
    if has_key_links?
      @_key_links_cache_key = "kl-" + Digest::SHA256.hexdigest(key_links.pluck(:id).join(","))
    else
      @_key_links_cache_key = nil
    end
  end

  # Override #reload to also reset various memoized attributes.
  def reset_memoized_attributes
    super
    remove_instance_variable(:@_has_key_links) if defined?(@_has_key_links)
    remove_instance_variable(:@_custom_key_links_active) if defined?(@_custom_key_links_active)
    remove_instance_variable(:@_key_links_cache_key) if defined?(@_key_links_cache_key)
  end
end
