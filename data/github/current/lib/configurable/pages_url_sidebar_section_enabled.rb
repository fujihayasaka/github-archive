# typed: strict
# frozen_string_literal: true

module Configurable
  module PagesUrlSidebarSectionEnabled
    extend T::Sig
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "pages_url_sidebar_section_enabled"

    sig { params(actor: User).returns(T::Boolean) }
    def disable_pages_url_sidebar_section(actor)
      config.disable!(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_pages_url_sidebar_section(actor)
      config.delete(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def pages_url_sidebar_section_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
