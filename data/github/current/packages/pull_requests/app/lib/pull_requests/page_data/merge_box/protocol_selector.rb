# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class ProtocolSelector
    include GitHub::Memoizer
    class Protocol
      include UrlHelpers
      extend T::Helpers
      abstract!
      sealed!

      sig { returns(T::Boolean) }
      attr_accessor :is_default

      sig { returns(Repository) }
      attr_reader :repository

      sig { params(repository: Repository).void }
      def initialize(repository)
        @repository = repository
        @is_default = T.let(false, T::Boolean)
      end

      sig { abstract.returns(String) }
      def url; end

      sig { abstract.returns(String) }
      def sticky_url; end

      sig { abstract.returns(T::Boolean) }
      def available?; end

      sig { abstract.returns(Symbol) }
      def to_sym; end
    end

    class SSHProtocol < Protocol
      sig { override.returns(String) }
      def url
        repository.ssh_url
      end

      sig { override.returns(String) }
      def sticky_url
        user_set_protocol_path({
          protocol_selector: "ssh",
          protocol_type: ("push"),
        })
      end

      sig { override.returns(T::Boolean) }
      def available?
        repository.ssh_enabled?
      end

      sig { override.returns(Symbol) }
      def to_sym
        :ssh
      end
    end

    class HTTPProtocol < Protocol
      sig { override.returns(String) }
      def url
        repository.http_url
      end

      sig { override.returns(String) }
      def sticky_url
        user_set_protocol_path({
          protocol_selector: "http",
          protocol_type: ("push"),
        })
      end

      sig { override.returns(T::Boolean) }
      def available?
        !repository.ssh_certificate_requirement_enabled?
      end

      sig { override.returns(Symbol) }
      def to_sym
        :http
      end
    end

    sig { returns(User) }
    attr_reader :user

    sig { returns(T.nilable(Repository)) }
    attr_reader :repository

    sig { params(repository: T.nilable(Repository), user: User).void }
    def initialize(repository:, user:)
      @repository = repository
      @user = user
    end

    sig { returns(T::Array[Protocol]) }
    memoize def protocols
      return [] unless repository

      repo_protocols = [SSHProtocol.new(T.must(repository)), HTTPProtocol.new(T.must(repository))]
      set_default(repo_protocols)
      repo_protocols
    end

    private

    sig { params(repo_protocols: T::Array[Protocol]).void }
    def set_default(repo_protocols)
      selected = repository&.protocol_selector(user).push_protocol.to_sym
      default_prot = repo_protocols.find { |prot| prot.to_sym == selected && prot.available? } || repo_protocols.find(&:available?)
      default_prot.is_default = true unless default_prot.nil?
    end
  end
end
