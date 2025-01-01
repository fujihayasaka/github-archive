# typed: strict
# frozen_string_literal: true

module Configurable
  module ReleasesSidebarSectionEnabled
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "releases_sidebar_section_enabled"

    sig { params(actor: User).returns(T::Boolean) }
    def disable_releases_sidebar_section(actor)
      config.disable!(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_releases_sidebar_section(actor)
      config.delete(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def releases_sidebar_section_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
