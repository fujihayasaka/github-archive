# Vonage JWT Generator for Ruby

[![Gem Version](https://badge.fury.io/rb/vonage-jwt.svg)](https://badge.fury.io/rb/vonage-jwt)![Coverage Status](https://github.com/Vonage/vonage-jwt-ruby/workflows/CI/badge.svg)[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg)](CODE_OF_CONDUCT.md)

This is the Ruby library to generate Vonage JSON Web Tokens (JWTs). To use it you'll
need a Vonage account. Sign up [for free at vonage.com][signup].

* [Requirements](#requirements)
* [Installation](#installation)
* [Usage](#usage)
* [Documentation](#documentation)
* [License](#license)

## Requirements

The JWT generator supports Ruby version 2.7 or newer.

## Installation

To install the Ruby client library using Rubygems:

    gem install vonage-jwt

Alternatively you can clone the repository:

    git clone git@github.com:Vonage/vonage-jwt-ruby.git

## Usage

### Generating a JWT

By default the Vonage JWT generator creates a short lived JWT (15 minutes) per request.
To generate a long lived JWT for multiple requests, specify a longer value in the `exp`
parameter during initialization.

Example with no custom configuration:

```ruby
@builder = Vonage::JWTBuilder.new(application_id: YOUR_APPLICATION_ID, private_key: YOUR_PRIVATE_KEY)
@token = @builder.jwt.generate
```

Example providing custom configuration options:

```ruby
@builder = Vonage::JWTBuilder.new(
  application_id: YOUR_APPLICATION_ID,
  private_key: YOUR_PRIVATE_KEY,
  ttl: 500,
  paths: {
    "acl": {
      "paths": {
        "/messages": {
          "methods": ["POST", "GET"],
          "filters": {
            "from": "447977271009"
          }
        }
      }
    }
  },
  subject: 'My_Custom_Subject'
)
@token = @builder.jwt.generate
```

### Decoding a JWT

You can decode a JWT like so:

```ruby
Vonage::JWT.decode(token, nil, false)
```

where `token` is the JWT that you want to decode. The `Vonage::JWT::decode` method is essentially just a wrapper around the `ruby-jwt` library method of the same name, and usage is identical to what is [documented for that library](https://github.com/jwt/ruby-jwt#algorithms-and-usage).

### Verifying a Signature

For JWTs that are signed, you can verify a JWT signature like so:

```ruby
Vonage::JWT.verify_signature(token, signature_secret, algorithm)
```

where `token` is the signed JWT, `signature_secret` is the secret or key required by whichever algorithm was used to sign the JWT, and `algorithm` is a string indicating the algorithm that was used to sign the JWT (e.g. `'HS256'`, `'RS256'`, etc)

The method will return `true` if the signature is verified and `false` if it is not.

## Documentation

Vonage Ruby JWT documentation: https://www.rubydoc.info/github/Vonage/vonage-jwt

Vonage Ruby code examples: https://github.com/Vonage/vonage-ruby-code-snippets

Vonage API reference: https://developer.vonage.com/api

## License

This library is released under the [MIT License][license]

[signup]: https://ui.idp.vonage.com/ui/auth/registration?utm_source=DEV_REL&utm_medium=github&utm_campaign=ruby-client-library
[license]: LICENSE.txt
