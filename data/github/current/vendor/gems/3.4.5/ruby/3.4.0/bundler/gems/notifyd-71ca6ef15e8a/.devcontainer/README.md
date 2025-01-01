# notifyd devcontainer

## Permissions

Our devcontainer permissions contain a wildcard for all `github` org repositories, _and_ explicit permissions for some repositories.
This appears to be redundant, but it's actually necessary!

The explicit permissions for repositories are used for prebuilds because wildcard permissions are not supported.
The wildcard permissions are used to create the `GITHUB_TOKEN` inside the codespace when launched, where they _are_ supported.

```json
      "repositories": {
        "github/*": {
          "permissions": {
            "contents": "read",
            "packages": "read"
          }
        },
        "github/features": {
          "permissions": {
            "contents": "read",
            "packages": "read"
          }
        },
      ...
      }
```
