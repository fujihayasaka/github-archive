# Azure

Our Azure backend works as follows:

- Each repository has a backing Azure DevOps `Tenant`, additionally, the owner of the repository (whether that is an Organization or a User) also has a backing Azure DevOps `Tenant`
- Each `Tenant` has a single `Project` with a single `Pipeline`, used for all builds from all workflows
- When a GH Repository has an action triggered, an `Tenant` with its related resources are created, see `azp/provider.InitializeProvider`
    - AZP Tenant creation is authenticated via Service Principal Auth - see `s2s_client.go`
    - The credentials for SP Auth are stored inside an Azure KeyVault instance.
    - To gain access to the creds in the KeyVault we authenticate as a AD App which is defined in a per
      environment AD Tenant owned by GitHub.
        - This GH AD App is registered/installed inside the MS AD tenant, and given access to the KeyVault
        - We ask the Microsoft AD Tenant for a Token for the vault as the GH AD App, and retrieve the key
        - With the key we can ask the AD Tenant for a token to access the AZP AD Resource
        - With that token we can make AZP API requests as the SP
- The AZP Tenant is owned by a AD user (currently)
- When we queue AZP Builds, or hit other AZP APIs for a GH Repo, we authenticate as the AZP Tenant via its AZP Service Identity
    - See `repository_client.go`
    - We ask AZP for a token to act as the AZP Service Identity
    - We can then make AZP API requests
- Each `CheckSuite` relates to an AZP Build, with `CheckRun`s relating to AZP Jobs and `CheckStep`s relating to AZP Actions (aka AZP Steps)
- We receive postbacks from AZP to update our Check entities

See glossary for all the Azure specific terms

## Entity relations

```


─────────┼   One to one



         ╱
──────────   One to many
         ╲

```

### Build/repo entities

```
┌──────────────────────────┐           ┌──────────────────────────┐
│                          │           │                          │
│                          │           │                          │
│      GH Repository       │           │                          │
│        (per env)         │──────────┼│     AZP Organization     │
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
└──────────────────────────┘           └──────────────────────────┘
                                                     │
                                                    ╱│╲
                                       ┌──────────────────────────┐
                                       │                          │
                                       │                          │
                                       │                          │
                                       │       AZP Project        │
                                       │                          │
                                       │                          │
                                       │                          │
                                       └──────────────────────────┘   Note: we have only a
                                                     │                single Project with a
                                                    ╱│╲              single Pipeline per AZP
                                       ┌──────────────────────────┐            Org
                                       │                          │
                                       │                          │
                                       │                          │
                                       │       AZP Pipeline       │
                                       │                          │
                                       │                          │
                                       │                          │
                                       └──────────────────────────┘
                                                     │
                                                    ╱│╲
┌──────────────────────────┐           ┌──────────────────────────┐
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
│        CheckSuite        │ ─────────┼│        AZP Build         │
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
└──────────────────────────┘           └──────────────────────────┘
              │                                      │
             ╱│╲                                    ╱│╲
┌──────────────────────────┐           ┌──────────────────────────┐
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
│        CheckRun          │──────────┼│         AZP Job          │
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
└──────────────────────────┘           └──────────────────────────┘
              │                                      │
             ╱│╲                                    ╱│╲
┌──────────────────────────┐           ┌──────────────────────────┐
│                          │           │                          │
│                          │           │                          │
│                          │           │         AZP Step         │
│        CheckStep         │─────────┼ │ (aka `steps:` in .yaml)  │
│                          │           │                          │
│                          │           │                          │
│                          │           │                          │
└──────────────────────────┘           └──────────────────────────┘
```

### Authorization identities

(diagrams/azure.monopic)

```
┌──────────────────────────┐
│                          │
│                          │                                 ┌────────────────────────────────────────────┐
│    Launch Application    │                                 │              GitHub AD Tenant              │
│  Environment (prod/lab)  │───────────────┐                 │                (AZ Tenant)                 │
│                          │               │                 │                                            │
│                          │               │                 │         ┌─────────────────────────┐        │
│                          │               └───────────────┼ │         │                         │        │
└──────────────────────────┘                                 │         │                         │        │
              │                                              │         │         AD App          │────────┼───────────────┐
              │                                              │         │                         │        │               │
              ├──────────────────────────────┐               │         │                         │        │               │
              │                              │               │         └─────────────────────────┘        │               │
             ╱│╲                             │               └────────────────────────────────────────────┘               │
┌──────────────────────────┐                 ┼                                                                            │
│                          │   ┌──────────────────────────┐                                                               │
│                          │   │                          │                                                               │
│                          │   │                          │               ┌───────────────────────────────────────────────┼─────────────┐
│      GH Repository       │   │                          │               │                     Microsoft AD Tenant       │             │
│                          │   │    Service Principal     │──────────┐    │                                               │             │
│                          │   │                          │          │    │                                               │             │
│                          │   │                          │          │    │                                               │             │
└──────────────────────────┘   │                          │          │    │                                               ┼             │
              │                └──────────────────────────┘          │    │                                    ┌─────────────────────┐  │
              │                                                      │    │  ┌──────────────────────────────┐  │ AD App Registration │  │
              │                                                      │    │  │            Vault             │  │                     │  │
              │                                                      │    │  │   ┌──────────────────────┐   │  └─────────────────────┘  │
              ┼                                                      │    │  │   │                      │   │             │             │
┌──────────────────────────┐                                         │    │  │   │Service Principal cert│   │             │             │
│                          │                                         └────┼──┼──┼│                      │┼──┼─────────────┘             │
│                          │                                              │  │   │                      │   │                           │
│    Organization Owner    │                                              │  │   └──────────────────────┘   │                           │
│        (AZP User)        │                                              │  └──────────────────────────────┘                           │
│                          │                                              │                                                             │
│                          │                                              │                                                             │
│                          │                                              │                                                             │
└──────────────────────────┘                                              └─────────────────────────────────────────────────────────────┘
              │
              ┼
┌──────────────────────────┐       ┌──────────────────────────┐        ┌──────────────────────────┐
│                          │       │                          │        │                          │
│                          │       │                          │        │                          │
│                          │       │                          │        │                          │
│     AZP Organization     │──────┼│       AZP Project        │───────┼│       AZP Pipeline       │
│                          │       │                          │        │                          │
│                          │       │                          │        │                          │
│                          │       │                          │        │                          │
└──────────────────────────┘       └──────────────────────────┘        └──────────────────────────┘
              │
              │
              ┼
┌──────────────────────────┐
│                          │
│                          │
│                          │
│   AZP Service Identity   │
│                          │
│                          │
│                          │
└──────────────────────────┘
```

## References

- ADRs in Dreamlifter:
    - Service to service identities: https://github.com/github/dreamlifter/blob/master/docs/adrs/0306-service-to-service-credential-setup.md
    - [Per repo creds](https://github.com/github/dreamlifter/issues/382)
- [Dreamlifter docs](https://github.com/github/dreamlifter/tree/master/docs)
- `azp_resources.go` docs for information on how we ensure only a single AZP org is created per repo per environment.

## Dashboards and UI

- https://dev.azure.com - AZD's portal, login with the Organization Owner accounts to see the resources
- https://portal.azure.com - AZ's portal, useful to checking on AD resources like AD Apps etc

## History

- [Organization creation/setup tracking issue](https://github.com/github/pe-actions-experience/issues/891)


## Glossary

- AD App - an application registered in AD, distinct from GitHub Applications
- AZP Build - a run of a given AZP Pipeline
- Active Directory (AD) - Microsoft authentication/authorization system
- Azure (AZ) - the general Microsoft SaaS offering, we use AD from there
- Azure DevOps (AZD) - the Microsoft product offering CI and various project management tools. Used to be called Team Foundation Server (TFS), Visual Studio Online/Visual Studio Team Services
- Azure Pipelines (AZP) - the CI part of Azure DevOps
- Service Identity - an AZP only concept, which represents a non-user entity making API requests
- Service Principal - an AD concept, which represents a non-user authorization entity, that can perform API requests
- Tenant - an instance of Active Directory or another Microsoft Cloud Service. Think "the GitHub tenancy inside the Microsoft owned building"

### Confusable terms

- AD Application vs GitHub Application
    - AD Apps live in Active Directory and represent and application for API auth, installation (App Registrations in AD UI) etc.
    - GitHub Applications are installable on GH Repos, and can use the GH APIs.
