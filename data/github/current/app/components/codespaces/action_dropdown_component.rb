# typed: true
# frozen_string_literal: true

module Codespaces
  class ActionDropdownComponent < ApplicationComponent
    include CodespacesHelper

    attr_reader :codespace, :allow_codespace_interaction, :keep_disabled, :allow_change_machine_type, :needs_fork_to_push

    EDITOR_TO_DESCRIPTORS_MAP = {
      Codespaces::Settings::PREFERRED_EDITOR_VSCODE_WEB => { label: "Open in Browser", icon: :globe, beta: false },
      Codespaces::Settings::PREFERRED_EDITOR_VSCODE => { label: "Open in Visual Studio Code", icon: :"device-desktop", beta: false  },
      Codespaces::Settings::PREFERRED_EDITOR_JETBRAINS => { label: "Open in JetBrains Gateway", icon: :"device-desktop", beta: true  },
      Codespaces::Settings::PREFERRED_EDITOR_JUPYTER => { label: "Open in JupyterLab", icon: :"device-desktop", beta: true  },
    }

    def initialize(codespace:, allow_codespace_interaction:, allow_change_machine_type:, needs_fork_to_push:)
      @codespace = codespace
      @allow_codespace_interaction = allow_codespace_interaction
      @keep_disabled = !Codespaces::Keep.new(codespace).can_keep?
      @allow_change_machine_type = allow_change_machine_type
      @needs_fork_to_push = needs_fork_to_push
    end

    def start_disabled?
      GitHub.flipper[:codespaces_disable_starts].enabled?(codespace.owner)
    end

    def show_open_options?
      !codespace.blocking_operation? && allow_codespace_interaction && !start_disabled?
    end

    def show_delete?
      codespace.deletable?(current_user)
    end

    def export_disabled?
      codespace.creation_failed? || codespace.blocking_operation?
    end

    def change_machine_type_disabled?
      codespace.creation_failed? || codespace.blocking_operation?
    end

    memoize def destroy_hydro_attributes
      destroy_codespace_attributes(codespace: codespace)
    end

    memoize def suspend_hydro_attributes
      suspend_codespace_attributes(codespace: codespace)
    end

    memoize def existing_fork
      codespace.repository_id && codespace.owner.repositories.find_by_parent_id(codespace.repository_id)
    end

    def change_machine_type_codespace_id
      "change-machine-type-codespace-#{codespace.id}-dialog"
    end

    def rename_codespace_id
      "rename-codespace-#{codespace.id}-dialog"
    end

    def delete_codespace_id
      "delete-codespace-#{codespace.id}-dialog"
    end

    def export_codespace_id
      "export-codespace-#{codespace.id}-dialog"
    end

    def export_fork_codespace_id
      "export-fork-codespace-#{codespace.id}-dialog"
    end

    def publish_codespace_id
      "publish-codespace-#{codespace.id}-dialog"
    end

    def delete_confirmation_message
      if codespace.has_unpushed_changes?
        "#{codespace.safe_display_name} has unpushed changes, are you sure you want to delete?"
      else
        "Are you sure you want to delete #{codespace.safe_display_name}?"
      end
    end
  end
end
