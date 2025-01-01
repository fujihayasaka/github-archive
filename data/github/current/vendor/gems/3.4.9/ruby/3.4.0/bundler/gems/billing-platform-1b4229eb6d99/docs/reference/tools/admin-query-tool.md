# Admin Query Tool

The Admin Query Tool is a web-based tool that allows you to run SQL queries against Cosmos DB. It is useful for running ad-hoc queries, troubleshooting, and debugging.

The data admin tool is currently deployed to the dotcom, staff and EU stamps. Each stamp has a different database, so make sure you're accessing the tool for the correct environment. You can access to tool by navigating to the following URLs in your web browser and authenticating with Okta:

- Dotcom stamp: https://billing-platform-admin-prod-dotcom.githubapp.com
- Staff stamp: https://billing-platform-admin-staffwus201.githubapp.com/
- EU stamp: https://billing-platform-admin-prodweu01.githubapp.com/

## Table of Contents

- [Details](#details)
  - [Tool permissions](#tool-permissions)
  - [This tool is read-only](#this-tool-is-read-only)
  - [Development access to the tool](#development-access-to-the-tool)
  - [Logging queries](#logging-queries)
- [References](#references)

## Details

### Tool permissions

All billing team members have access to the tool. If you're outside this team and need access you can [add yourself to the `billing-platform-admin` entitlement](https://github.com/github/entitlements/blob/master/ldap/apps/okta-network-gateway/billing-platform-admin.txt).

### This tool is read-only

The admin query tool is read only. You can only run SELECT queries against the database. This is to prevent accidental data modification. This is enforced by our read-only SPN in Cosmos.

[Credentials for the SPN are enrolled to autocred](https://github.com/github/autocred/blob/main/docs/azure_app_registrations/ONBOARDING.md#does-autocred-work-for-me).

- [Creating an SPN](https://github.com/github/azure-rbac/blob/main/docs/service_principal_names.md)
- [Read only SPN notes](https://github.slack.com/archives/C0454035N9Z/p1707173418293509?thread_ts=1707171018.348249&cid=C0454035N9Z)

### Development access to the tool

In development you can start the query tool and other services by running `script/server`. We do some checks that you are Okta authenticated when running a query, so you will need to use the oktaproxy tool in development (which is started with `script/server`) to simulate that.

The admin tool runs on port 8888 and the oktaproxy runs on 8899. Use the following URL to access the admin tool in development:

http://127.0.0.1:8899

### Logging queries

For audit purposes we log all queries performed and which user made the query. This is logged to Splunk. You can find those logs with the following search query:

[``` index="billing"  InstrumentationScope=BillingPlatformAdmin Body="Performing query from admin tool" ```](https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3D%22billing%22%20%20InstrumentationScope%3DBillingPlatformAdmin%20Body%3D%22Performing%20query%20from%20admin%20tool%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-60m%40m&latest=now&sid=1712173725.428670_6F675BFE-E002-4BA9-BC57-B70B5EBC6803)

![Log example](/docs/images/log.png)

## References

- :movie_camera: [There is a demo of the admin query tool available on Rewatch](https://github.rewatch.com/video/fvwb8ak9p8b76oyj-billing-platform-admin-tool-demo).
