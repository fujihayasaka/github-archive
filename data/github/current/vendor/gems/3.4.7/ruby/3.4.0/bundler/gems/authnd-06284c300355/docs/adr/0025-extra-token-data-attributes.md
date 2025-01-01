# 25. Extra token data attributes

Date: 2021-03-25

## Status

Accepted

## Context

Some credential types, specifically SignedAuthTokens, provide the generator with the ability to store additional data in the token that can be retrieved by the validating code.
This data takes the form of key-value pairs, where the key is any string and the value is any Ruby "primitive" type (numbers, strings, booleans).
When authenticating these credential types, we will need to retrieve this data and return it to the caller.

For example, a SignedAuthToken can be generated like this:

```ruby
# Generate a SAT for 'user'
token = user.signed_auth_token(scope: "MyScope", expires: 8.hours.from_now, data: { app_id: 123, page: "/foo/bar" })
```

This SAT has two payload entries associated with it:

* `app_id = 123`
* `page = "/foo/bar`

These payload values must be provided in the response from authnd when authenticating the token so that the caller has access to them.

## Decision

We'll provide this data in the form of added attributes, one for each key-value pair.
The name of each attribute will be `credential.payload:[key]`, where `[key]` is the original key from the credential payload.
The value will be whatever value was stored in the token type.
If a value in the token is of a type that cannot be represented in our existing `Value` type, it will be omitted
(in the future, we can expand allowed value types or serialize certain types differently, such as representing dates as strings or integers).

With the example token above, the payload would be returned as the following attributes:

* `credential.payload:app_id = 123`
* `credential.payload:page = "/foo/bar"`

## Consequences

One alternative option would have been to add a single attribute `credential.payload` with a new `Value` type that describes a set of key-value pairs.
Using our existing attribute list for this allows us to avoid having to introduce new data types to our existing `Value` protobuf message and keep it relatively well-aligned with authzd.

Another alternative option is to add another field to the `Response` containing a separate set of `Attribute`s that represent the "payload" of the credential.
Introducing a separate set of attributes seems like a source of confusion.
Using a single attribute list means it's easy for callers to know where to look.
Only callers that actually expect a payload value need to look for the special prefix.

Using a prefix means that in order for callers to extract values they must know to apply the prefix.
For example, if a caller knows that a value `foo` was put into the token for their use, they need to know to access it via `credential.payload:foo`.
We could simplify this by adding a `.payload` property in our clients that provides a hash of just the `credential.payload:` values.

Using a different separator (`:` instead of our usual `.`) to separate the prefix from the key name helps us maintain consistency between how an "attribute ID" (like `actor.id`) is formatted,
while still allowing free-form key-value pairs in the payload.
We will treat `:` as "reserved" and disallow it's use in our own attribute IDs.

Using a prefix also protects against a payload value conflicting with an attribute ID.
If a token contains an `actor.id` payload value, it will be represented in the returned attributes as `credential.payload:actor.id` and will not conflict with the `actor.id` attribute.