# typed: strict
# frozen_string_literal: true

module Configurable
  module EnvironmentsSidebarSectionEnabled
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "environments_sidebar_section_enabled"

    sig { params(actor: User).returns(T::Boolean) }
    def disable_environments_sidebar_section(actor)
      config.disable!(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_environments_sidebar_section(actor)
      config.delete(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def environments_sidebar_section_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
