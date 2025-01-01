# 2. Develop in Go

Date: 2020-09-29

## Status

Accepted

## Context

We need a common understanding of the tools being used to produce the product and why they are being used.

## Decision

We will use the Go programming language.

We will use existing GitHub Go libraries from https://github.com/github/go where possible.

## Consequences

Go is a well-established language for modern services at GitHub. Authentication is a high-traffic area of the product
and performance is critical, so Go is a good choice for this product. Go is suited to building container-based applications
and has a broad community of users inside and outside GitHub.

GitHub has a wide array of libraries to support us and there are many subject matter experts available to help understand
these libraries.