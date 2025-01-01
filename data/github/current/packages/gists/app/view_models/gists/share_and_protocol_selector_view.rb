# typed: false
# frozen_string_literal: true

module Gists
  class ShareAndProtocolSelectorView < ::Repositories::ProtocolSelectorView

    def initialize(context:, repository:, user: nil, base_url: nil)
      super context: context, repository: repository, user: user
      @base_url = base_url
    end

    # Overrides apply_context which dynamically populates the protocol list
    # based on the situation with our static list for gist.
    def apply_context(_)
      @protocols << :embed
      @protocols << :share
      @protocols << :http
      @protocols << :ssh if ssh_available?
    end

    # Overriedes the default protocol to force it to be embed. For repos
    # this returns the users saved preference if any.
    def determine_default_protocol(_)
      :embed
    end

    # Overrides to use Gist's custom view model.
    def each_protocol_view
      return to_enum(__method__) unless block_given?
      @protocols.each do |protocol|
        yield Gists::ShareAndCloneURLView.new(
          repository: repository,
          type: protocol,
          is_default: protocol == @default_protocol,
          pushable: @pushable,
          base_url: @base_url,
        )
      end
    end

  end
end
