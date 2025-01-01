# typed: strict
# frozen_string_literal: true

module Copilot
  class GetStartedWithCopilotComponent < ApplicationComponent
    extend T::Sig
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
    end

    sig { returns(T.nilable(String)) }
    memoize def component_subtitle
      return "Start using Copilot to secure your seat" if copilot_user.has_cfb_access?
      return "Setup Copilot in a few steps" if copilot_user.has_trial_subscription?
      "You have an active Copilot subscription"
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def tools
      [
        { id: "vscode", name: "Visual Studio Code", anchor_id: "prerequisites-2" },
        { id: "jetbrains", name: "JetBrains", anchor_id: "prerequisites" },
        { id: "visualstudio", name: "Visual Studio", anchor_id: "prerequisites-1" },
        { id: "vimneovim", name: "Vim/Neovim", anchor_id: "prerequisites-3" }
      ]
    end
  end
end
