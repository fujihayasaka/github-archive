# typed: true
# frozen_string_literal: true

class AppAssociations::AndroidIdentitiesController < AppAssociations::BaseController
  # This needs to be specified because ApplicationController, which
  # `AppAssociations::BaseController` inherits from, does some feature flag
  # checks and those checks hit the Mysql1 cluster.
  depends_on_clusters ApplicationRecord::Mysql1

  # This path is used to verify the github.com domain as the host of
  # all the deep links (or app links) used in the GitHub Android app.
  # It contains an entry for each of our apps (Dev, Staff, Production).
  def index
    # Forcing content-type header directly to application/json
    response.headers["Content-Type"] = "application/json"
    render json: <<~JSON
    [{
      "relation": ["delegate_permission/common.handle_all_urls"],
      "target": {
        "namespace": "android_app",
        "package_name": "com.github.android.dev",
        "sha256_cert_fingerprints": [
          "94:53:53:34:54:66:B1:30:4B:3C:67:9D:E7:9C:C2:AA:77:E4:4E:FF:1B:1A:F8:D9:64:C8:79:82:16:CC:88:68",
          "3C:B3:96:8D:FD:F5:17:27:EC:DD:C2:EB:08:D8:27:BF:45:63:43:59:35:1F:FA:DD:6B:FD:2D:8A:E0:D0:68:6B"
        ]
      }
    },{
      "relation": ["delegate_permission/common.handle_all_urls"],
      "target": {
        "namespace": "android_app",
        "package_name": "com.github.android.staff",
        "sha256_cert_fingerprints": [
          "F6:50:1D:96:30:92:5A:AF:2E:AF:B0:CE:51:F5:43:C6:BE:89:D8:68:C8:3F:92:05:06:A4:6F:E5:DA:49:AA:2E"
        ]
      }
    },{
      "relation": ["delegate_permission/common.handle_all_urls"],
      "target": {
        "namespace": "android_app",
        "package_name": "com.github.android",
        "sha256_cert_fingerprints": [
          "DF:08:C9:F2:D8:09:18:9D:9D:50:64:97:C1:57:45:A7:39:5A:41:53:6E:FB:43:3E:3A:EE:1A:ED:BE:11:B2:61"
        ]
      }
    }]
    JSON
  end
end
