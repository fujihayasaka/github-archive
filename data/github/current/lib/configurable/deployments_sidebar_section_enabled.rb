# typed: strict
# frozen_string_literal: true

module Configurable
  module DeploymentsSidebarSectionEnabled
    extend T::Helpers
    include Kernel

    requires_ancestor { Configurable }

    KEY = "deployments_sidebar_section_enabled"

    sig { params(actor: User).returns(T::Boolean) }
    def disable_deployments_sidebar_section(actor)
      config.disable!(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def enable_deployments_sidebar_section(actor)
      config.delete(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def deployments_sidebar_section_enabled?
      config.enabled?(KEY) || config.get(KEY).nil?
    end
  end
end
