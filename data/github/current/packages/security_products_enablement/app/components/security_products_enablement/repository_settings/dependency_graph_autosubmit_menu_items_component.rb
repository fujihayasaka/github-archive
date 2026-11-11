# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class DependencyGraphAutosubmitMenuItemsComponent < ApplicationComponent
    extend T::Helpers

    DISABLED = "disabled"
    ENABLED = "enabled"
    ENABLED_WITH_LABEL = "enabled_with_label"

    sig { returns(Repository) }
    attr_reader :repository

    sig do
      params(
        repository: Repository,
        service_enabled: T::Boolean,
        labeled_runners_enabled: T::Boolean,
        labeled_runners_available: T::Boolean,
      ).void
    end
    def initialize(repository:, service_enabled:, labeled_runners_enabled:, labeled_runners_available:)
      @repository = repository
      @service_enabled = service_enabled
      @labeled_runners_enabled = labeled_runners_enabled
      @labeled_runners_available = labeled_runners_available
    end

    sig { returns(String) }
    def current_state
      if service_enabled? && use_labelled_runners?
        ENABLED_WITH_LABEL
      elsif service_enabled?
        ENABLED
      else
        DISABLED
      end
    end

    sig { returns(String) }
    def form_url
      update_security_products_settings_path(repository.owner, repository)
    end

    sig { returns(T::Boolean) }
    def blocked_by_actions?
      !repository.actions_enabled?
    end

    sig { returns(T::Boolean) }
    def blocked_by_runner_labels?
      !labeled_runners_available?
    end

    sig { returns(String) }
    def enabled_description
      render(Primer::Beta::Text.new(tag: :div).with_content("Use standard GitHub runners"))
    end

    sig { returns(String) }
    def enabled_for_labelled_description
      render(Primer::Beta::Text.new(tag: :div).with_content("Use runners labeled with 'dependency-submission'"))
    end

    sig { returns(String) }
    def actions_disabled_warning
      return "" unless blocked_by_actions?

      render(Primer::Beta::Text.new(tag: :div, color: :attention).with_content("Actions have been disabled"))
    end

    sig { returns(String) }
    def labelled_runners_unavailable_warning
      return "" if blocked_by_actions? # If Actions has been disabled, that takes precedent.
      return "" unless blocked_by_runner_labels?

      render(Primer::Beta::Text.new(tag: :div, color: :attention).with_content("No runners with this label assigned to repository"))
    end

    private

    sig { returns(T::Boolean) }
    def service_enabled?
      @service_enabled
    end

    sig { returns(T::Boolean) }
    def use_labelled_runners?
      @labeled_runners_enabled
    end

    sig { returns(T::Boolean) }
    def labeled_runners_available?
      @labeled_runners_available
    end
  end
end
