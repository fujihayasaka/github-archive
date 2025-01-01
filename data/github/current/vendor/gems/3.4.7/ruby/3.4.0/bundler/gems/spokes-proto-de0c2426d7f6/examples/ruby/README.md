# Spokes API Ruby client example

This directory includes a simple Ruby program that runs a request against a bootstrapped copy of this repository.

```
spokes-proto$ script/bootstrap
spokes-proto$ docker compose up -d
spokes-proto$ cd examples/ruby
example-ruby$ bash bootstrap.sh
example-ruby$ source env.sh
example-ruby$ bundle exec ruby main.rb
```
