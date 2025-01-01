# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  class ActionSelectionListItemMenuComponent < ActionSelectionListItemBaseComponent
    def disabled?
      case @action
      when :none
        super
      else
        false
      end
    end

    def render?
      case @action
      when :read
        !Permissions::ResourceRegistry.writeonly_subject_type?(@resource)
      when :write
        !Permissions::ResourceRegistry.readonly_subject_type?(@resource)
      else
        super
      end
    end
  end
end
