# typed: true
# frozen_string_literal: true

module Repos
  module CodeViewPayloads
    class LayoutRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewLayoutRoute"
      end

      def payload
        @payload
      end
    end

    class FileTreeLayoutRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewFileTreeLayoutRoute"
      end

      def payload
        @payload
      end
    end

    class TreeRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewTreeRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the files#disambiguate route (overview view)
    class OverviewRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewRepoRoute"
      end

      def payload
        @payload
      end
    end

    class OverviewHeaderPayload < ::ReactPayload::Partial
      def route_id
        "codeViewRepoRoute.Header"
      end
    end

    class OverviewSidebarPayload < ::ReactPayload::Partial
      def route_id
        "codeViewRepoRoute.Sidebar"
      end
    end

    class OverviewSidebarAboutPayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "sidebarAbout"
      end

      def payload
        @payload
      end
    end

    class BlobLayoutPayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewBlobLayoutRoute"
      end

      def payload
        @payload
      end
    end

    class BlobLayoutStyledBlobPayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewBlobLayoutRoute.StyledBlob"
      end

      def payload
        @payload
      end
    end

    # Payload for the blob#show route
    class BlobShowRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewBlobRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the blob#new route
    class BlobNewRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewNewRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the blob#edit route
    class BlobEditRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewEditRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the blob#blame route
    class BlobBlameRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewBlameRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the tree#delete route
    class TreeDeleteRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewTreeDeleteRoute"
      end

      def payload
        @payload
      end
    end

    # Payload for the blob#delete route
    class BlobDeleteRoutePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "codeViewDeleteRoute"
      end

      def payload
        @payload
      end
    end

    class FileTreePayload < ::ReactPayload::Base
      def initialize(payload)
        @payload = payload
      end

      def route_id
        "fileTree"
      end

      def payload
        @payload
      end
    end
  end
end
