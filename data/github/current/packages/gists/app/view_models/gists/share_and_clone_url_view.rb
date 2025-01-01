# typed: false
# frozen_string_literal: true

module Gists
  class ShareAndCloneURLView < ::Files::CloneURLView
    class URLs < ViewModel::URLs
      # Override base_url with manually supplied value
      attr_reader :base_url

      def initialize(base_url)
        @base_url = base_url
      end
    end

    alias_method :gist, :repository
    attr_reader :base_url

    def urls
      @urls ||= Gists::ShareAndCloneURLView::URLs.new(base_url)
    end

    def protocol
      super || type.to_s.titlecase
    end

    def url
      super
    rescue ArgumentError
      case type
      when :share
        permalink_url
      when :embed
        script_tag = helpers.content_tag(:script, "", src: embed_url)
        ERB::Util.force_escape(script_tag)
      else
        raise ArgumentError, "unknown type: %p" % type
      end
    end

    private

    def embed_url
      "#{urls.base_url}#{urls.user_gist_path(gist.user_param, gist, format: :js)}"
    end

    def permalink_url
      "#{urls.base_url}#{urls.user_gist_path(gist.user_param, gist)}"
    end

  end
end
