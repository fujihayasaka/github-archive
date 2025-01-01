# typed: true
# frozen_string_literal: true

module GhostPilot
  class SuggestionsComponent < ApplicationComponent

    include GhostPilotHelper

    VERSION = "0.0.19"
    VERSION_DESC = "suggest only to end of sentence"

    NEXT_VERSION = "1.0.0"
    NEXT_VERSION_DESC = "initial GA"

    EDITOR_VERSION = "#{VERSION} - #{VERSION_DESC}"
    NEXT_EDITOR_VERSION = "#{NEXT_VERSION} - #{NEXT_VERSION_DESC}"

    attr_reader :source_element_id, :element_description, :context, :accessible_dialog_id

    sig do
      params(
        source_element_id: String,
        element_description: String,
        context: T::Array[BaseContextComponent],
      ).void
    end
    def initialize(source_element_id:, element_description:, context: [])
      @source_element_id = source_element_id
      @element_description = element_description
      @context = context
      @accessible_dialog_id = "copilot-text-completion-accessible-dialog"
    end

    def context_element_ids
      @context.map do |c|
        if c.feature_flag.present?
          c.element_id if user_feature_enabled?(c.feature_flag)
        else
          c.element_id
        end
      end.compact
    end

    def enabled?
      @enabled = current_user.feature_preview_enabled?(:ghost_pilot_pr_autocomplete)
    end

    def allow_cors?
      !Rails.env.development?
    end

    def version
      if current_user.feature_enabled?(:ghost_pilot_vnext)
        NEXT_VERSION
      else
        VERSION
      end
    end

    def version_with_description
      if current_user.feature_enabled?(:ghost_pilot_vnext)
        NEXT_EDITOR_VERSION
      else
        EDITOR_VERSION
      end
    end
  end
end
