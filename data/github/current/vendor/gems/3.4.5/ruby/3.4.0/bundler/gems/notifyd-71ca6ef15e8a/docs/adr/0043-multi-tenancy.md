# 43. Multi-Tenancy management

Date: 2023-06-29

## Status

Accepted

## Context

With the arrive of [Proxima], GitHub has to support [multi-tenant environments][multi-tenant-fag]. In this environment it is expected that the data and operations of a tenant is isolated from others, and this is done mainly at the application level.

Each tenant is defined by its slug (used as a subdomain like `avocado.ghe.com`) and its ID (an `int64` that is unique).

In order to ensure that operations for a given tenant are respected by different services, the tenant data has to be propagated among these services using a [set of standard headers][multi-tenant-services]:

* `X-GitHub-Tenant`: with the slug
* `X-GitHub-Tenant-ID`: with the ID

It is up to each service to propagate this data and to enforce data isolation if needed.

In the context of Notifyd, the service needs both values, not only to propagate them on calls to the Monolith and other services, but for internal operations as well:

* The slug is needed to build email address for `Reply-To`, `List-Unsubscribe` and `From` email header fields (for example `Reply-To: <reply+ABC@reply.avocado.ghe.com>`)
* The ID will be needed for data isolation, although this work still needs to be defined

## Decision

The concept of tenant is rooted to the environment the app runs. Each request and background job is tied to a tenant, and this tenant can be used in any layer of the app: it defines email addresses, outgoing propagation headers and more.

We could require tenant data depending on whether we are in a multi-tenant environment or not, but that could create different execution branches in many places.

In order to have a consistent way to handle tenants inside Notifyd in multi and single tenant environments, we want to introduce the `Tenant` interface that will be passed as an argument across layers during runtime execution.

This will help us in the following ways:

* We will have the concept of `Tenant` rooted in the architecture of the app. We always have a tenant, it doesn't matter which environment. The only difference is that in some environments (like Production) the tenant is always the same.
* We will have an explicit dependency across boundaries, avoiding possible runtime errors because we depend on implicit dynamic dependencies that depend on the current execution `Context`.

This essentially means that a lot of our service interfaces will require a new argument:

```go
// BEFORE
type SomeService interface {
    DoSomething(context.Context, Data)
}

// AFTER
type SomeService interface {
    DoSomething(context.Context, tenancy.Tenant, Data)
}
```

A `Tenant` is an interface, and it provides the basic methods to set, get and check multi tenant environments:

```go
type Tenant interface {
    IsMultiTenant() bool
    Slug() string
    ID() int64
    WithSlug(string) Tenant
    WithID(int64) Tenant
    // ...
}
```

Concrete implementations of `Tenant` will be `SingleTenant` and `MultiTenant`. With these types, we can delegate how a tenant behaves in different environments without spreading these decisions all over our app.

## Consequences

Passing a `Tenant` as a runtime dependency across services and other types means that we need to change a lot code to add this dependency. Most of the entry point methods have to be updated and the `Tenant` has to be passed across many layers. It's a big change that can make the experience of working with `Tenant` cumbersome since it's always there, passed around. However this also means the compiler will tell us when we are missing the `Tenant`, when is not used, or when an interface that expects it is not properly defined.

[Proxima]: https://thehub.github.com/initiatives/proxima/
[multi-tenant-fag]: https://github.com/github/proxima/blob/main/docs/tenancy/proxima-faqs.md
[multi-tenant-services]: https://github.com/github/proxima/blob/main/docs/tenancy/multi-tenancy-services.md#tenant-context-propagation
