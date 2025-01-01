# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class BannersDataPayload
    extend T::Sig
    class Banners
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.any(T::Boolean, String)]) }
      attr_accessor :dependabot_automated_security_updates

      sig { returns(T::Hash[Symbol, T::Boolean]) }
      attr_accessor :paused_dependabot_update

      sig { returns(T::Hash[Symbol, T::Boolean]) }
      attr_accessor :hidden_character_warning

      sig { void }
      def initialize
        @dependabot_automated_security_updates = T.let({}, T::Hash[Symbol, T.any(T::Boolean, String)])
        @paused_dependabot_update = T.let({ render: false }, T::Hash[Symbol, T::Boolean])
        @hidden_character_warning = T.let({ render: false }, T::Hash[Symbol, T::Boolean])
      end
    end
    sig { returns(Banners) }
    attr_reader :banners

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        repository: Repository
      ).returns(T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]])
    end
    def self.build(current_user:, pull_request:, repository:)
      banners = new(current_user:, pull_request:, repository:)
      banners.build
      banners.to_hash
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        repository: Repository
      ).void
    end
    def initialize(current_user:, pull_request:, repository:)
      @current_user = current_user
      @pull_request = pull_request
      @repository = repository

      @banners = T.let(Banners.new, Banners)
    end

    sig { void }
    def build
      determine_banners
    end

    sig { returns(T::Hash[Symbol, T::Hash[Symbol, T::Hash[Symbol, Object]]]) }
    def to_hash
      {
        banners: {
          dependabotAutomatedSecurityUpdates: @banners.dependabot_automated_security_updates,
          pausedDependabotUpdate: @banners.paused_dependabot_update,
          hiddenCharacterWarning: @banners.hidden_character_warning
        },
      }
    end

    private

    sig { void }
    def determine_banners
      dependabot_automated_security_updates = PullRequests::PageData::BannersLoaders::DependabotAutomatedSecurityUpdatesLoader.build(
        current_user: @current_user,
        pull_request: @pull_request,
        repository: @repository
      )
      paused_dependabot_update = PullRequests::PageData::BannersLoaders::PausedDependabotUpdateLoader.build(
        current_user: @current_user,
        pull_request: @pull_request
      )
      hidden_characters = PullRequests::PageData::BannersLoaders::HiddenCharactersLoader.build(
        pull_request: @pull_request,
        repository: @repository
      )

      @banners.dependabot_automated_security_updates = dependabot_automated_security_updates
      @banners.paused_dependabot_update = paused_dependabot_update
      @banners.hidden_character_warning = hidden_characters
    end
  end
end
