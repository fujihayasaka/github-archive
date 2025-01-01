# typed: true
# frozen_string_literal: true

require_relative "../../models/viewscreen" # rubocop:disable ViewComponent/ComponentsHaveUnitTests
require_relative "../../models/notebook"

module CodeRenderingService
  module OriginUrlResolver

    class << self
      extend T::Sig
      # Returns the scheme, domain, and tld of the origin passed in for the viewscreen, notebooks, and github services.
      # e.g. "https://www.viewscreen.#{GitHub.user_content_host_name}.com/path/to/pdf.pdf" => "https://www.viewscreen.#{GitHub.user_content_host_name}.com"
      # e.g. "https://www.notebooks.#{GitHub.user_content_host_name}.com/path/to/notebook.ipynb" => "https://www.notebooks.#{GitHub.user_content_host_name}.com"

      sig { params(origin: T.nilable(String)).returns(String) }
      def host_url(origin)
        origin = origin.to_s

        if GitHub.enterprise? && !GitHub.subdomain_isolation? && !GitHub.multi_tenant_enterprise?
          return host_url_for_enterprise_non_subdomain_isolated(origin)
        end

        host_url_for_dotcom_or_enterprise_subdomain_isolated(origin)
      end

      private

      sig { params(origin: String).returns(String) }
      def host_url_for_enterprise_non_subdomain_isolated(origin)
        if URI.parse(origin).path&.start_with? GitHub.viewscreen_path_prefix
          Viewscreen.host_url
        elsif URI.parse(origin).path&.start_with? GitHub.notebooks_path_prefix
          Notebook.host_url
        else
          ""
        end
      rescue
        ""
      end

      sig { params(origin: String).returns(String) }
      def host_url_for_dotcom_or_enterprise_subdomain_isolated(origin)
        if URI.parse(origin).host == URI.parse(Viewscreen.host_url).host
          Viewscreen.host_url
        elsif URI.parse(origin).host == URI.parse(Notebook.host_url).host
          Notebook.host_url
        else
          ""
        end
      rescue
        ""
      end
    end
  end
end
