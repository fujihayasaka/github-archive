# GhConfig

Common Github configuration options shared by several applications.

Use this gem to add configuration methods such as `enterprise?` to your application.

Call `reload_config` from your initializers to load the configuration options from the `config.yml` file in the root directory if it exists.


## Installation

Add this line to your application's Gemfile:

    gem 'ghconfig'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ghconfig

## Usage

Include `GhConfig` in the module that controls your app's configuration:

```ruby
module Gists
  module Config
    include GhConfig
  end
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
