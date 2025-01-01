# typed: false
# frozen_string_literal: true

module Repositories
  class ProtocolSelectorView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include Repos::SshCertificateHelper

    attr_reader :repository, :user

    def initialize(context:, repository:, user: nil)
      @repository = repository
      @user = user
      @pushable = repository.pushable_by? user
      @protocols = []
      apply_context context
      @default_protocol = determine_default_protocol @protocols
    end

    def pushable?
      @pushable
    end

    def default
      @default ||= each_protocol_view.detect { |view| view.is_default }
    end

    def default_url
      default.url
    end

    def each_protocol_view
      return to_enum(__method__) unless block_given?
      @protocols.each do |protocol|
        yield Files::CloneURLView.new(
          repository: repository,
          type: protocol,
          is_default: protocol == @default_protocol,
          pushable: @pushable,
        )
      end
    end

    def protocol_view_for(type)
      found_view = each_protocol_view.detect { |view| view.type == type }
      raise ArgumentError, "unavailable protocol %p" % type unless found_view
      found_view
    end

    def selector
      @selector ||= repository.protocol_selector(user)
    end

    def apply_context(context)
      case context
      when :empty_repo
        @protocols << :http if http_available?
        @protocols << :ssh if ssh_available?
      when :repo_header
        @protocols << :http if http_available?
        @protocols << :ssh if ssh_available?
        @protocols << :gh_cli
      when :merge_help
        @protocols << :http if http_available?
        @protocols << :ssh if ssh_available?
      else
        raise ArgumentError, "unknown context"
      end
      @protocols.freeze
    end

    def determine_default_protocol(available_protocols = @protocols)
      protocol_type = @pushable ? :push_protocol : :clone_protocol
      selected = selector.send(protocol_type).to_sym
      suggested = GitHub.suggested_protocol.to_sym

      if available_protocols.include? suggested
        suggested
      elsif available_protocols.include? selected
        selected
      else
        available_protocols.first
      end
    end

    def ssh_available?
      user && repository.ssh_enabled?
    end

    def http_available?
      !ssh_certificates_required?
    end

    def ssh_certificates_available?
      ssh_available? && can_use_ssh_certificates?(user: user, repository: repository)
    end

    def ssh_certificates_required?
      user && repository.ssh_certificate_requirement_enabled?
    end

    def authentication_required?
      GitHub.private_mode_enabled? || repository.private?
    end

    def show_clone_warning?
      user && user.public_keys.none? && !ssh_certificates_available?
    end
  end
end
