# typed: strict
# frozen_string_literal: true

module Copilot
  class GetStartedWithCopilotComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(T.any(Copilot::User, Copilot::Public::User)) }
    attr_reader :copilot_user

    sig { params(copilot_user: T.any(Copilot::User, Copilot::Public::User), dfd_trial: T::Boolean).void }
    def initialize(copilot_user, dfd_trial: false)
      @copilot_user = T.let(copilot_user, T.any(Copilot::User, Copilot::Public::User))
      @dfd_trial = T.let(dfd_trial, T::Boolean)
    end

    sig { returns(T.nilable(String)) }
    memoize def component_subtitle
      return "Start using Copilot to secure your seat" if copilot_user.has_cb_access?
      return "Setup Copilot in a few steps" if copilot_user.has_trial_access?
      "You have an active Copilot subscription"
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def tools
      [
        { id: "vscode", name: "Visual Studio Code", anchor_id: "prerequisites-2" },
        { id: "jetbrains", name: "JetBrains", anchor_id: "prerequisites" },
        { id: "visualstudio", name: "Visual Studio", anchor_id: "prerequisites-1" },
        { id: "vimneovim", name: "Vim/Neovim", anchor_id: "prerequisites-3" },
        { id: "eclipse", name: "Eclipse", anchor_id: "prerequisites-4" },
        { id: "xcode", name: "Xcode", anchor_id: "prerequisites-5" },
      ]
    end

    sig { returns(T::Boolean) }
    def dfd_trial?
      @dfd_trial
    end
  end
end
