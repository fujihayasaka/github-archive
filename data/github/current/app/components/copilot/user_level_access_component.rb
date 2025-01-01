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
    end

    sig { returns(String) }
    memoize def plan_type
      return "enterprise" if copilot_user.has_cfe_access? || copilot_user.copilot_plan == "enterprise"
      return "business" if copilot_user.has_cfb_access? || has_copilot_standalone_business?
      "individual"
    end

    sig { returns T::Boolean }
    memoize def has_copilot_standalone_business?
      copilot_user.has_copilot_standalone_business?
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def docs
      doc_links = [
        { id: "ide", name: "Copilot in your IDE", scheme: :primary, url: "copilot/get-started-with-copilot" },
        { id: "cli", name: "Copilot in the CLI", scheme: :default, url: "copilot/github-copilot-in-the-cli" },
        { id: "mobile", name: "Chat in GitHub Mobile", scheme: :default, url: "copilot/github-copilot-chat" },
      ]

      doc_links << { id: "dotcom_chat", name: "Copilot in github.com", scheme: :default, url: "copilot/copilot-chat-in-github" } if copilot_user.has_cfe_access? || copilot_user.copilot_plan == "enterprise"
      doc_links << { id: "more", name: "More features", scheme: :default, url: "copilot/home", fragment: "all-docs" }
      doc_links
    end

    sig { returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
    memoize def copilot_provider
      copilot_user.copilot_provider
    end

    sig { returns(T.nilable(String)) }
    memoize def copilot_provider_path
      provider = copilot_provider&.__getobj__

      return if provider.nil?

      # copilot_provider is always guaranteed to be a business or an org
      if provider.is_a? ::Business
        enterprise_path(provider)
      else
        user_path(provider)
      end
    end
  end
end
