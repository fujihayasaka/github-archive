# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class DependencyGraphAutosubmitComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    sig { returns(T::Boolean) }
    def render?
      data.dependency_graph_autosubmit_action_visible
    end

    sig { returns(T::Boolean) }
    def blocked_by_actions?
      !repository.actions_enabled?
    end

    sig { returns(String) }
    memoize def current_state_label
      if enabled? && use_labelled_runners?
        "Enabled for labeled runners"
      elsif enabled?
        "Enabled"
      else
        "Disabled"
      end
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      false
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      security_configuration = enforced_security_configuration
      return false unless security_configuration

      security_configuration.dependency_graph_autosubmit_action != "not_set"
    end

    private

    sig { returns(T::Boolean) }
    def enabled?
      data.dependency_graph_autosubmit_action_enabled
    end

    sig { returns(T::Boolean) }
    def use_labelled_runners?
      data.dependency_graph_autosubmit_action_use_labeled_runners
    end
  end
end
