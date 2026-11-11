# typed: strict
# frozen_string_literal: true

module Copilot
  class UserLevelAccessComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
      @edu_ui_enabled = T.let(false, T::Boolean)
    end

    sig { void }
    def before_render
      @edu_ui_enabled = feature_enabled_globally_or_for_user?(feature_name: "copilot_student_ui")
    end

    sig { returns(T::Boolean) }
    def edu_ui_enabled?
      @edu_ui_enabled
    end

    sig { returns(String) }
    memoize def plan_type
      return "enterprise" if copilot_user.has_cfe_access? || copilot_user.copilot_plan == "enterprise"
      return "business" if copilot_user.has_cfb_access? || has_copilot_standalone_business?
      return "education" if copilot_user.has_educational_access? && edu_ui_enabled?
      return "max" if copilot_user.has_max_access?
      return "pro+" if copilot_user.has_pro_plus_access?
      "pro"
    end

    sig { returns T::Boolean }
    memoize def has_copilot_standalone_business?
      copilot_user.has_copilot_standalone_business?
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def docs
      doc_links = [
        { id: "ide", name: "Copilot in your IDE", scheme: :primary, url: "copilot/get-started-with-copilot" },
        { id: "cli", name: Copilot::Policies::Cli.display_name, scheme: :default, url: Copilot::Policies::Cli.doc_url_scheme },
        { id: "mobile", name: "Chat in GitHub Mobile", scheme: :default, url: "copilot/copilot-chat-in-mobile" },
      ]

      doc_links << { id: "dotcom_chat", name: "Copilot in GitHub.com", scheme: :default, url: "copilot/copilot-chat-in-github" } if copilot_user.has_cfe_access? || copilot_user.copilot_plan == "enterprise"
      doc_links << { id: "more", name: "More features", scheme: :default, url: "copilot/features" }
      doc_links
    end

    sig { returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
    memoize def copilot_provider
      copilot_user.copilot_provider
    end
  end
end
