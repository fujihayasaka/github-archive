# typed: true
# frozen_string_literal: true

module GitHub
  # Internal: Chooses a push or clone URL for a Repository.
  class RepositoryProtocolSelector
    PushableProtocols = %w(http ssh subversion gh_cli).freeze
    CloneableProtocols = %w(http ssh gitweb subversion gh_cli).freeze

    # repository - The Repository object with GitRepository::UrlMethods.
    # user       - Optional User with #protocols Hash.
    def initialize(repository, user = nil)
      @repository = repository
      @user = user
    end

    # Public: Gets the protocol for pushing to this Repository.
    #
    # Returns a String protocol name from PushableProtocols.
    def push_protocol
      protocols = PushableProtocols
      protocols = ["local"] + protocols if GitHub::AppEnvironment.development?
      protocol_for(:push, protocols)
    end

    # Public: Gets the protocol for cloning this Repository.
    #
    # Returns a String protocol name from CloneableProtocols.
    def clone_protocol
      protocols = CloneableProtocols
      protocols -= ["gitweb"] if @repository.private?
      protocol_for(:clone, protocols)
    end

    # Public: Gets the URL to push to this Repository.
    #
    # Returns a String URL.
    def push_url
      @repository.send("#{push_protocol}_url")
    end

    # Public: Gets the URL to clone this Repository.
    #
    # Returns a String URL.
    def clone_url
      @repository.send("#{clone_protocol}_url")
    end

    # Looks up the protocol of the given type from the given selections.
    #
    # type       - A String protocol name.
    # selections - Array of possible String protocol names.
    #
    # Returns a String protocol name.
    def protocol_for(type, selections)
      user_protocol_for(type, selections) || selections.first
    end

    # Looks up the preferred protocol for the given user.
    #
    # type       - A String protocol name.
    # selections - Array of possible String protocol names.
    #
    # Returns a String protocol name, or nil if the User has no preferrence.
    def user_protocol_for(type, selections)
      return nil unless protos = @user && @user.protocols
      return nil unless choice = protos[type.to_s]
      selections.detect { |sel| sel == choice }
    end
  end
end
